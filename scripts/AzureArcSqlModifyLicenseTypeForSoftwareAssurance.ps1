#Requires -Version 7.2

<#
Purpose
-------
This runbook adjusts the Azure Arc-enabled SQL Server extension LicenseType setting
to match the expected value derived from the discovered SQL Server edition, based on
the Microsoft documentation below and the Software Assurance scenario adopted for
this environment.

Documentation References
------------------------
License types:
https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/manage-license-billing?view=sql-server-ver17#license-types

Transition to pay-as-you-go:
https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/manage-pay-as-you-go-transition?view=sql-server-ver17

Microsoft sample:
https://github.com/microsoft/sql-server-samples/tree/master/samples/manage/azure-arc-enabled-sql-server/modify-license-type

Expected mapping used by this runbook
------------------------------------
- Enterprise or Standard edition -> Paid
- Developer, Evaluation, or Express edition -> LicenseOnly

Important disclaimer
--------------------
- This runbook is intended to align Arc SQL LicenseType settings with Microsoft
  documentation and the organization's Software Assurance interpretation.
- This automation is an operational aid and not legal, licensing, or contractual advice.
- Validate the expected behavior in your environment before broad production use.
- This runbook only targets machines that are:
  - Connected in Azure Arc
  - Using the SQL Server Arc extension
  - In extension provisioning state Succeeded
  - Already inventoried with a supported SQL edition, or with a missing LicenseType
    that can be inferred from inventory
- Machines awaiting inventory or requiring manual review are intentionally excluded
  from remediation.

Validation query
----------------
Use the query below in Azure Resource Graph to review the current compliance state
before or after remediation.

resources
| where type =~ "microsoft.hybridcompute/machines"
| extend machineResourceId = id
| extend ComputerName = name
| extend joinID = toupper(id)
| extend AgentStatus = tostring(properties.status)
| where AgentStatus =~ "Connected"
| project machineResourceId, ComputerName, joinID, AgentStatus, ResourceGroup = resourceGroup, subscriptionId
| join kind=inner (
    resources
    | where type =~ "microsoft.hybridcompute/machines/extensions"
    | extend ExtensionType = tostring(properties.type)
    | where ExtensionType in~ ("WindowsAgent.SqlServer", "LinuxAgent.SqlServer")
    | extend ExtensionProvisioningState = tostring(properties.provisioningState)
    | where ExtensionProvisioningState =~ "Succeeded"
    | extend machineId = toupper(substring(id, 0, indexof(id, "/extensions")))
    | extend extensionName = tostring(split(id, "/extensions/")[1])
    | extend RawLicenseType = tostring(properties.settings.LicenseType)
    | extend LicenseActual = iff(isempty(RawLicenseType), "Configuration needed", RawLicenseType)
    | extend LicenseActualNormalized = case(
        isempty(RawLicenseType), "Configuration needed",
        RawLicenseType =~ "paid", "Paid",
        RawLicenseType =~ "payg", "PAYG",
        RawLicenseType =~ "licenseonly" or RawLicenseType =~ "lic", "LicenseOnly",
        RawLicenseType
    )
    | summarize
        extensionName = any(extensionName),
        ExtensionProvisioningState = any(ExtensionProvisioningState),
        LicenseActual = any(LicenseActual),
        LicenseActualNormalized = any(LicenseActualNormalized)
      by machineId
) on $left.joinID == $right.machineId
| join kind=leftouter (
    resources
    | where type =~ "microsoft.azurearcdata/sqlserverinstances"
    | extend machineLink = toupper(tostring(properties.containerResourceId))
    | extend Edition = tostring(properties.edition)
    | extend Version = tostring(properties.version)
    | extend EditionPriority = case(
        Edition =~ "Enterprise", 5,
        Edition =~ "Standard", 4,
        Edition =~ "Developer", 3,
        Edition =~ "Evaluation", 2,
        Edition =~ "Express", 1,
        0
    )
    | where EditionPriority > 0
    | summarize arg_max(EditionPriority, Edition, Version) by machineLink
) on $left.joinID == $right.machineLink
| extend Edition = coalesce(Edition, "N/A")
| extend Version = coalesce(Version, "N/A")
| extend SuggestedLicenseType = case(
    Edition in~ ("Enterprise", "Standard"), "Paid",
    Edition in~ ("Developer", "Evaluation", "Express"), "LicenseOnly",
    Edition == "N/A", "Awaiting inventory",
    "Review"
)
| extend ComplianceStatus = case(
    SuggestedLicenseType in ("Paid", "LicenseOnly") and LicenseActualNormalized == SuggestedLicenseType, "Compliant",
    SuggestedLicenseType in ("Paid", "LicenseOnly") and LicenseActual == "Configuration needed", "Pending (Configuration needed)",
    SuggestedLicenseType in ("Paid", "LicenseOnly") and LicenseActualNormalized != SuggestedLicenseType, "Non-compliant",
    Edition == "N/A", "Pending (Awaiting inventory)",
    "Review"
)
| extend Details = case(
    ComplianceStatus == "Non-compliant", strcat("Current LicenseType is ", LicenseActualNormalized, "; expected ", SuggestedLicenseType, " for SQL edition ", Edition),
    ComplianceStatus == "Pending (Configuration needed)", strcat("LicenseType is not configured; expected ", SuggestedLicenseType, " for SQL edition ", Edition),
    ComplianceStatus == "Pending (Awaiting inventory)", "SQL inventory is not available yet for this Arc machine.",
    ComplianceStatus == "Compliant", strcat("Current LicenseType already matches expected value: ", SuggestedLicenseType),
    "Review required"
)
| project
    machineResourceId,
    ComputerName,
    AgentStatus,
    ExtensionProvisioningState,
    Edition,
    Version,
    extensionName,
    LicenseActual,
    LicenseActualNormalized,
    SuggestedLicenseType,
    ComplianceStatus,
    ResourceGroup,
    subscriptionId,
    Details
| order by ComplianceStatus asc, Edition asc, ComputerName asc
#>

$ErrorActionPreference = "Stop"

$ReportOnly = $false
$BatchSize = 500
$ExtensionApiVersion = "2025-01-13"

$script:LogBuffer = [System.Collections.Generic.List[string]]::new()
$script:ArmAccessToken = $null

function Write-Log {
    param (
        [ValidateSet("INFO", "WARN", "ERROR", "FATAL", "RESULT", "SUCCESS")]
        [string] $Level,
        [string] $Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $script:LogBuffer.Add("[$timestamp][$Level] $Message")
}

function Flush-Logs {
    foreach ($line in $script:LogBuffer) {
        Write-Output $line
    }
}

function Normalize-String {
    param (
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return ""
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    return $text.Trim()
}

function Format-ResultValue {
    param (
        [AllowNull()]
        [object] $Value
    )

    return (Normalize-String $Value) -replace ",", ";"
}

function Get-ErrorResponseBody {
    param (
        [System.Exception] $Exception
    )

    try {
        if ($null -eq $Exception) {
            return $null
        }

        if ($Exception.PSObject.Properties.Name -contains "ErrorDetails") {
            $details = Normalize-String $Exception.ErrorDetails.Message
            if (-not [string]::IsNullOrWhiteSpace($details)) {
                return $details
            }
        }

        if ($null -eq $Exception.Response) {
            return $null
        }

        try {
            if ($Exception.Response.PSObject.TypeNames -contains "System.Net.Http.HttpResponseMessage") {
                $content = $Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $content = Normalize-String $content
                if (-not [string]::IsNullOrWhiteSpace($content)) {
                    return $content
                }
            }
        }
        catch {
        }

        $stream = $Exception.Response.GetResponseStream()
        if ($null -eq $stream) {
            return $null
        }

        $reader = New-Object System.IO.StreamReader($stream)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    }
    catch {
        return $null
    }
}

function Invoke-AzCli {
    param (
        [string[]] $Arguments
    )

    $output = & az @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = [string](($output | Out-String).Trim())

    if ($exitCode -ne 0) {
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw "Azure CLI command failed with exit code $exitCode."
        }

        throw "Azure CLI command failed: $text"
    }

    return $text
}

function Get-AuthHeaders {
    $token = Get-ArmAccessToken

    return @{
        Authorization = "Bearer $token"
        "Content-Type" = "application/json"
    }
}

function Test-Prerequisites {
    Write-Log INFO "Validating prerequisites."

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI was not found. Use a Hybrid Runbook Worker or an environment where Azure CLI is available."
    }

    $versionRaw = Invoke-AzCli -Arguments @("version", "--output", "json", "--only-show-errors")
    $cliVersion = ($versionRaw | ConvertFrom-Json)."azure-cli"

    Write-Log INFO "Azure CLI $cliVersion | PowerShell $($PSVersionTable.PSVersion)"
    Write-Log SUCCESS "Prerequisites validated."
}

function Install-RequiredExtensions {
    Write-Log INFO "Ensuring required Azure CLI extensions are installed."

    [void](Invoke-AzCli -Arguments @(
        "config", "set",
        "extension.use_dynamic_install=yes_without_prompt",
        "--only-show-errors"
    ))

    [void](Invoke-AzCli -Arguments @(
        "extension", "add",
        "--name", "resource-graph",
        "--upgrade",
        "--only-show-errors"
    ))

    Write-Log SUCCESS "Required Azure CLI extensions are ready."
}

function Connect-Azure {
    Write-Log INFO "Authenticating to Azure CLI with managed identity."

    [void](Invoke-AzCli -Arguments @(
        "login",
        "--identity",
        "--allow-no-subscriptions",
        "--output", "none",
        "--only-show-errors"
    ))

    $script:ArmAccessToken = $null
    Write-Log SUCCESS "Authentication completed."
}

function Get-AccessibleSubscriptionIds {
    Write-Log INFO "Discovering accessible enabled subscriptions for the managed identity."

    $subscriptionRaw = Invoke-AzCli -Arguments @(
        "account", "list",
        "--all",
        "--query", "[?state=='Enabled'].id",
        "--output", "tsv",
        "--only-show-errors"
    )

    $subscriptionIds = @(
        $subscriptionRaw -split "\r?\n" |
        ForEach-Object { Normalize-String $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    )

    if ($subscriptionIds.Count -eq 0) {
        throw "No enabled subscription was found for the managed identity."
    }

    Write-Log SUCCESS "Accessible enabled subscriptions found: $($subscriptionIds.Count)."
    return @($subscriptionIds)
}

function Get-ArmAccessToken {
    if (-not [string]::IsNullOrWhiteSpace($script:ArmAccessToken)) {
        return $script:ArmAccessToken
    }

    $token = Invoke-AzCli -Arguments @(
        "account", "get-access-token",
        "--resource", "https://management.azure.com/",
        "--query", "accessToken",
        "--output", "tsv",
        "--only-show-errors"
    )

    $token = Normalize-String $token

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Failed to retrieve an ARM access token."
    }

    $script:ArmAccessToken = $token
    return $script:ArmAccessToken
}

function Get-TargetMachines {
    param (
        [int] $PageSize,
        [string[]] $SubscriptionIds
    )

    $queryFile = Join-Path ([IO.Path]::GetTempPath()) "arg_$([guid]::NewGuid().ToString('N')).kql"

    $kql = @'
resources
| where type =~ "microsoft.hybridcompute/machines"
| extend machineResourceId = id
| extend ComputerName = name
| extend joinID = toupper(id)
| extend AgentStatus = tostring(properties.status)
| where AgentStatus =~ "Connected"
| project machineResourceId, ComputerName, joinID, AgentStatus, ResourceGroup = resourceGroup, subscriptionId
| join kind=inner (
    resources
    | where type =~ "microsoft.hybridcompute/machines/extensions"
    | extend ExtensionType = tostring(properties.type)
    | where ExtensionType in~ ("WindowsAgent.SqlServer", "LinuxAgent.SqlServer")
    | extend ExtensionProvisioningState = tostring(properties.provisioningState)
    | where ExtensionProvisioningState =~ "Succeeded"
    | extend machineId = toupper(substring(id, 0, indexof(id, "/extensions")))
    | extend extensionName = tostring(split(id, "/extensions/")[1])
    | extend RawLicenseType = tostring(properties.settings.LicenseType)
    | extend LicenseActual = iff(isempty(RawLicenseType), "Configuration needed", RawLicenseType)
    | extend LicenseActualNormalized = case(
        isempty(RawLicenseType), "Configuration needed",
        RawLicenseType =~ "paid", "Paid",
        RawLicenseType =~ "payg", "PAYG",
        RawLicenseType =~ "licenseonly" or RawLicenseType =~ "lic", "LicenseOnly",
        RawLicenseType
    )
    | summarize
        extensionName = any(extensionName),
        ExtensionProvisioningState = any(ExtensionProvisioningState),
        LicenseActual = any(LicenseActual),
        LicenseActualNormalized = any(LicenseActualNormalized)
      by machineId
) on $left.joinID == $right.machineId
| join kind=leftouter (
    resources
    | where type =~ "microsoft.azurearcdata/sqlserverinstances"
    | extend machineLink = toupper(tostring(properties.containerResourceId))
    | extend Edition = tostring(properties.edition)
    | extend Version = tostring(properties.version)
    | extend EditionPriority = case(
        Edition =~ "Enterprise", 5,
        Edition =~ "Standard", 4,
        Edition =~ "Developer", 3,
        Edition =~ "Evaluation", 2,
        Edition =~ "Express", 1,
        0
    )
    | where EditionPriority > 0
    | summarize arg_max(EditionPriority, Edition, Version) by machineLink
) on $left.joinID == $right.machineLink
| extend Edition = coalesce(Edition, "N/A")
| extend Version = coalesce(Version, "N/A")
| extend SuggestedLicenseType = case(
    Edition in~ ("Enterprise", "Standard"), "Paid",
    Edition in~ ("Developer", "Evaluation", "Express"), "LicenseOnly",
    Edition == "N/A", "Awaiting inventory",
    "Review"
)
| extend ComplianceStatus = case(
    SuggestedLicenseType in ("Paid", "LicenseOnly") and LicenseActualNormalized == SuggestedLicenseType, "Compliant",
    SuggestedLicenseType in ("Paid", "LicenseOnly") and LicenseActual == "Configuration needed", "Pending (Configuration needed)",
    SuggestedLicenseType in ("Paid", "LicenseOnly") and LicenseActualNormalized != SuggestedLicenseType, "Non-compliant",
    Edition == "N/A", "Pending (Awaiting inventory)",
    "Review"
)
| extend Details = case(
    ComplianceStatus == "Non-compliant", strcat("Current LicenseType is ", LicenseActualNormalized, "; expected ", SuggestedLicenseType, " for SQL edition ", Edition),
    ComplianceStatus == "Pending (Configuration needed)", strcat("LicenseType is not configured; expected ", SuggestedLicenseType, " for SQL edition ", Edition),
    ComplianceStatus == "Pending (Awaiting inventory)", "SQL inventory is not available yet for this Arc machine.",
    ComplianceStatus == "Compliant", strcat("Current LicenseType already matches expected value: ", SuggestedLicenseType),
    "Review required"
)
| where SuggestedLicenseType in ("Paid", "LicenseOnly")
| where LicenseActualNormalized != SuggestedLicenseType
| project
    machineResourceId,
    ComputerName,
    AgentStatus,
    ExtensionProvisioningState,
    Edition,
    Version,
    extensionName,
    LicenseActual,
    LicenseActualNormalized,
    SuggestedLicenseType,
    ComplianceStatus,
    ResourceGroup,
    subscriptionId,
    Details
| order by SuggestedLicenseType asc, Edition asc, ComputerName asc
'@

    try {
        Set-Content -Path $queryFile -Value $kql -Encoding UTF8 -Force

        $allData = @()
        $skip = 0

        do {
            $arguments = @(
                "graph", "query",
                "-q", "@$queryFile",
                "--subscriptions"
            ) + $SubscriptionIds + @(
                "--first", $PageSize.ToString(),
                "--skip", $skip.ToString(),
                "--output", "json",
                "--only-show-errors"
            )

            $json = Invoke-AzCli -Arguments $arguments
            $result = $json | ConvertFrom-Json
            $pageData = @($result.data)
            $pageCount = $pageData.Count

            if ($pageCount -gt 0) {
                $allData += $pageData
                $skip += $pageCount
            }

            Write-Log INFO "ARG page returned $pageCount row(s). Total loaded: $($allData.Count)."
        }
        while ($pageCount -eq $PageSize)

        if ($allData.Count -gt 0) {
            Write-Log INFO "ARG query completed. Remediation target count: $($allData.Count)."
        }
        else {
            Write-Log INFO "ARG query completed. No remediation targets were found."
        }

        return @($allData)
    }
    finally {
        if (Test-Path $queryFile) {
            Remove-Item $queryFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ExtensionResource {
    param (
        [string] $SubscriptionId,
        [string] $ResourceGroup,
        [string] $MachineName,
        [string] $ExtensionName,
        [string] $ApiVersion
    )

    $url = "https://management.azure.com/subscriptions/${SubscriptionId}/resourceGroups/${ResourceGroup}/providers/Microsoft.HybridCompute/machines/${MachineName}/extensions/${ExtensionName}?api-version=${ApiVersion}"

    try {
        return Invoke-RestMethod `
            -Method Get `
            -Uri $url `
            -Headers (Get-AuthHeaders)
    }
    catch {
        $responseBody = Get-ErrorResponseBody -Exception $_.Exception
        throw "Failed to read extension '$ExtensionName' on machine '$MachineName'. URL: $url. Error: $($_.Exception.Message). Body: $responseBody"
    }
}

function Test-TrueValue {
    param (
        [object] $Value
    )

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [bool]) {
        return $Value
    }

    return ($Value.ToString().ToLowerInvariant() -eq "true")
}

function Test-ExtensionApiAccess {
    param (
        [pscustomobject] $Target
    )

    Write-Log INFO "Validating extension API access with machine '$($Target.ComputerName)'."

    $null = Get-ExtensionResource `
        -SubscriptionId (Normalize-String $Target.subscriptionId) `
        -ResourceGroup (Normalize-String $Target.ResourceGroup) `
        -MachineName (Normalize-String $Target.ComputerName) `
        -ExtensionName (Normalize-String $Target.extensionName) `
        -ApiVersion $ExtensionApiVersion

    Write-Log SUCCESS "Extension API validation succeeded for '$($Target.ComputerName)'."
}

function Update-SqlArcLicenseType {
    param (
        [string] $SubscriptionId,
        [string] $ResourceGroup,
        [string] $MachineName,
        [string] $ExtensionName,
        [string] $TargetLicenseType,
        [string] $ApiVersion,
        [bool] $WhatIfMode
    )

    $current = Get-ExtensionResource `
        -SubscriptionId $SubscriptionId `
        -ResourceGroup $ResourceGroup `
        -MachineName $MachineName `
        -ExtensionName $ExtensionName `
        -ApiVersion $ApiVersion

    $settings = @{}
    if ($null -ne $current.properties.settings) {
        $settings = $current.properties.settings | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
    }

    $currentLicense = ""
    if ($settings.ContainsKey("LicenseType")) {
        $currentLicense = Normalize-String $settings["LicenseType"]
    }

    $esuEnabled = $false
    if ($settings.ContainsKey("enableExtendedSecurityUpdates")) {
        $esuEnabled = Test-TrueValue -Value $settings["enableExtendedSecurityUpdates"]
    }

    if ($TargetLicenseType -eq "LicenseOnly" -and $esuEnabled) {
        Write-Log WARN "Skipping '$MachineName': ESU is enabled and LicenseType cannot be changed to LicenseOnly."
        return "Skipped-ESUEnabled"
    }

    if ($currentLicense -ieq $TargetLicenseType) {
        Write-Log INFO "No change is required for '$MachineName'."
        return "AlreadyCompliant"
    }

    $settings["LicenseType"] = $TargetLicenseType

    $body = @{
        location = $current.location
        properties = @{
            publisher = $current.properties.publisher
            type = $current.properties.type
            typeHandlerVersion = $current.properties.typeHandlerVersion
            settings = $settings
        }
    }

    if ($null -ne $current.properties.autoUpgradeMinorVersion) {
        $body.properties["autoUpgradeMinorVersion"] = $current.properties.autoUpgradeMinorVersion
    }

    if ($null -ne $current.properties.enableAutomaticUpgrade) {
        $body.properties["enableAutomaticUpgrade"] = $current.properties.enableAutomaticUpgrade
    }

    if ($null -ne $current.tags) {
        $body["tags"] = $current.tags
    }

    $url = "https://management.azure.com/subscriptions/${SubscriptionId}/resourceGroups/${ResourceGroup}/providers/Microsoft.HybridCompute/machines/${MachineName}/extensions/${ExtensionName}?api-version=${ApiVersion}"

    if ($WhatIfMode) {
        Write-Log INFO "ReportOnly mode: no change applied to '$MachineName'. Target LicenseType: $TargetLicenseType."
        return "ReportOnly"
    }

    $jsonBody = $body | ConvertTo-Json -Depth 30

    try {
        $null = Invoke-RestMethod `
            -Method Put `
            -Uri $url `
            -Headers (Get-AuthHeaders) `
            -Body $jsonBody

        return "Success"
    }
    catch {
        $responseBody = Get-ErrorResponseBody -Exception $_.Exception
        throw "Failed to update '$MachineName'. URL: $url. Error: $($_.Exception.Message). Body: $responseBody"
    }
}

function Invoke-Remediation {
    param (
        [hashtable] $Stats,
        [string[]] $SubscriptionIds
    )

    $targets = Get-TargetMachines -PageSize $BatchSize -SubscriptionIds $SubscriptionIds

    if (-not $targets -or $targets.Count -eq 0) {
        Write-Log INFO "No out-of-policy Arc SQL machines were found."
        return
    }

    $Stats.Found = $targets.Count
    Write-Log INFO "Found $($targets.Count) machine(s) that require review or remediation."

    Test-ExtensionApiAccess -Target $targets[0]

    foreach ($m in $targets) {
        $machineName = Normalize-String $m.ComputerName
        $resourceGroup = Normalize-String $m.ResourceGroup
        $subscriptionId = Normalize-String $m.subscriptionId
        $agentStatus = Normalize-String $m.AgentStatus
        $extensionProvisioningState = Normalize-String $m.ExtensionProvisioningState
        $edition = Normalize-String $m.Edition
        $version = Normalize-String $m.Version
        $extensionName = Normalize-String $m.extensionName
        $currentLicense = Normalize-String $m.LicenseActualNormalized
        $targetLicense = Normalize-String $m.SuggestedLicenseType
        $complianceStatus = Normalize-String $m.ComplianceStatus
        $details = Normalize-String $m.Details

        Write-Log INFO "Processing '$machineName' | Subscription='$subscriptionId' | ResourceGroup='$resourceGroup' | AgentStatus='$agentStatus' | ExtensionState='$extensionProvisioningState' | Edition='$edition' | Current='$currentLicense' | Expected='$targetLicense'."

        try {
            $result = Update-SqlArcLicenseType `
                -SubscriptionId $subscriptionId `
                -ResourceGroup $resourceGroup `
                -MachineName $machineName `
                -ExtensionName $extensionName `
                -TargetLicenseType $targetLicense `
                -ApiVersion $ExtensionApiVersion `
                -WhatIfMode $ReportOnly

            switch ($result) {
                "Success" {
                    $Stats.Success++
                }
                "ReportOnly" {
                    $Stats.ReportOnly++
                }
                "AlreadyCompliant" {
                    $Stats.Skipped++
                }
                default {
                    if ($result -like "Skipped*") {
                        $Stats.Skipped++
                    }
                    else {
                        $Stats.Failure++
                    }
                }
            }

            Write-Log RESULT (
                (Format-ResultValue $machineName) + "," +
                (Format-ResultValue $resourceGroup) + "," +
                (Format-ResultValue $subscriptionId) + "," +
                (Format-ResultValue $agentStatus) + "," +
                (Format-ResultValue $extensionProvisioningState) + "," +
                (Format-ResultValue $edition) + "," +
                (Format-ResultValue $version) + "," +
                (Format-ResultValue $extensionName) + "," +
                (Format-ResultValue $currentLicense) + "," +
                (Format-ResultValue $targetLicense) + "," +
                (Format-ResultValue $complianceStatus) + "," +
                (Format-ResultValue $result) + "," +
                (Format-ResultValue $details)
            )
        }
        catch {
            $Stats.Failure++
            Write-Log ERROR "Failed to process '$machineName': $($_.Exception.Message)"

            Write-Log RESULT (
                (Format-ResultValue $machineName) + "," +
                (Format-ResultValue $resourceGroup) + "," +
                (Format-ResultValue $subscriptionId) + "," +
                (Format-ResultValue $agentStatus) + "," +
                (Format-ResultValue $extensionProvisioningState) + "," +
                (Format-ResultValue $edition) + "," +
                (Format-ResultValue $version) + "," +
                (Format-ResultValue $extensionName) + "," +
                (Format-ResultValue $currentLicense) + "," +
                (Format-ResultValue $targetLicense) + "," +
                (Format-ResultValue $complianceStatus) + "," +
                "Failure," +
                (Format-ResultValue $details)
            )
        }
    }
}

try {
    Write-Log INFO "=== Azure Arc SQL LicenseType Remediation Runbook ==="

    Test-Prerequisites
    Connect-Azure
    Install-RequiredExtensions

    $subscriptionIds = Get-AccessibleSubscriptionIds

    $stats = @{
        Found      = 0
        Success    = 0
        ReportOnly = 0
        Failure    = 0
        Skipped    = 0
    }

    Write-Log RESULT "MachineName,ResourceGroup,SubscriptionId,AgentStatus,ExtensionProvisioningState,Edition,Version,ExtensionName,CurrentLicense,TargetLicense,ComplianceStatus,UpdateResult,Details"

    Invoke-Remediation -Stats $stats -SubscriptionIds $subscriptionIds

    Write-Log INFO "=== SUMMARY ==="
    Write-Log INFO "Machines found: $($stats.Found)"
    Write-Log INFO "Machines updated successfully: $($stats.Success)"
    Write-Log INFO "Machines evaluated in report-only mode: $($stats.ReportOnly)"
    Write-Log INFO "Machines skipped: $($stats.Skipped)"
    Write-Log INFO "Machines failed: $($stats.Failure)"
    Write-Log INFO "=== Done ==="
}
catch {
    Write-Log FATAL "Execution failed: $($_.Exception.Message)"
    throw
}
finally {
    Flush-Logs
}
