<#
.SYNOPSIS
    Activates Software Assurance benefits on Azure Arc Windows machines.

.DESCRIPTION
    Queries all subscriptions for Azure Arc Windows machines where Software Assurance
    benefits are not activated, and enables them via REST API.

    Uses ONLY Azure CLI — no Az PowerShell modules required.

.NOTES
    Reference: https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-license-and-billing-for-extended-security-updates

.PREREQUISITES
    - PowerShell 7.2+ Runtime Environment
    - Azure CLI (pre-installed in Azure Automation)
    - Managed Identity with Reader + Azure Connected Machine Resource Administrator
#>

#Requires -Version 7.2

$ErrorActionPreference = "Stop"

# =============================================================================
# LOGGING
# =============================================================================
function Write-Log {
    param (
        [ValidateSet("INFO", "WARN", "ERROR", "FATAL", "RESULT")]
        [string] $Level,
        [string] $Message
    )
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][$Level] $Message"
}

# =============================================================================
# PREREQUISITES
# =============================================================================
function Test-Prerequisites {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw "Azure CLI not found." }
    $v = (az version --output json 2>$null | ConvertFrom-Json).'azure-cli'
    Write-Log INFO "Azure CLI $v | PowerShell $($PSVersionTable.PSVersion)"
}

function Install-RequiredExtensions {
    $installed = (az extension list --output json 2>$null | ConvertFrom-Json).name
    foreach ($ext in @("resource-graph")) {
        if ($ext -notin $installed) {
            Write-Log INFO "Installing extension '$ext'..."
            az extension add --name $ext --yes 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Failed to install extension '$ext'." }
        }
    }
}

# =============================================================================
# AUTHENTICATION
# =============================================================================
function Connect-Azure {
    Write-Log INFO "Authenticating with managed identity..."
    $out = az login --identity --allow-no-subscriptions 2>&1
    if ($LASTEXITCODE -ne 0) { throw "az login failed: $($out -join ' ')" }
    Write-Log INFO "Authenticated."
}

# =============================================================================
# RESOURCE GRAPH QUERY
# =============================================================================
function Get-TargetMachines {
    param ([string] $SubscriptionId)

    $queryFile = Join-Path ([IO.Path]::GetTempPath()) "arg_$([guid]::NewGuid().ToString('N')).kql"

    # KQL: Find eligible Windows Server Arc machines where Software Assurance is NOT activated
    # Eligible = Connected + Licensed. Pre-filtering removes "Not eligible" machines.
    $kql = @'
resources
| where type =~ "microsoft.hybridcompute/machines"
| where properties.osType =~ "windows"
| where tolower(tostring(properties.status)) == "connected"
| extend operatingSystem = tostring(properties.osSku)
| where operatingSystem has "Server"
| extend licenseProfile = coalesce(properties.licenseProfile, properties.licenseProfileStorage.properties)
| extend licenseStatus = tostring(licenseProfile.licenseStatus)
| where licenseStatus =~ "Licensed"
| extend licenseChannel = tostring(licenseProfile.licenseChannel)
| extend productSubscriptionStatus = tostring(licenseProfile.productProfile.subscriptionStatus)
| extend softwareAssurance = licenseProfile.softwareAssurance
| extend softwareAssuranceCustomer = licenseProfile.softwareAssurance.softwareAssuranceCustomer
| extend benefitsStatus = case(
    softwareAssuranceCustomer == true, "Activated",
    (licenseStatus =~ "Licensed" and licenseChannel =~ "PGS:TB") or productSubscriptionStatus =~ "Enabled", "Activated via Pay-as-you-go",
    isnull(softwareAssurance) or isnull(softwareAssuranceCustomer) or softwareAssuranceCustomer == false, "Not activated",
    "Not activated")
| where benefitsStatus =~ "Not activated"
| project machineName = name, resourceGroup, subscriptionId, operatingSystem, location, benefitsStatus
| where isnotempty(machineName) and isnotempty(resourceGroup)
'@

    try {
        Set-Content -Path $queryFile -Value $kql -Encoding UTF8 -Force

        $pageSize = 1000
        $skip = 0
        $allData = @()

        do {
            $json = az graph query -q "@$queryFile" --subscriptions $SubscriptionId `
                --first $pageSize --skip $skip --output json 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Resource Graph query failed: $($json -join ' ')" }

            $result = $json | ConvertFrom-Json
            $pageData = $result.data
            $pageCount = $pageData.Count

            if ($pageCount -gt 0) {
                $allData += $pageData
                $skip += $pageCount
            }

            if ($skip -gt $pageSize) {
                Write-Log INFO "Paginating Resource Graph: $($allData.Count) rows fetched so far..."
            }
        } while ($pageCount -eq $pageSize)

        return $allData
    }
    finally {
        if (Test-Path $queryFile) { Remove-Item $queryFile -Force -ErrorAction SilentlyContinue }
    }
}

# =============================================================================
# ENABLE SOFTWARE ASSURANCE
# PUT /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.HybridCompute/machines/{machine}/licenseProfiles/default
# =============================================================================
function Enable-SoftwareAssurance {
    param (
        [string] $SubscriptionId,
        [string] $ResourceGroup,
        [string] $MachineName,
        [string] $Location,
        [int]    $MaxRetries = 2
    )

    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.HybridCompute/machines/$MachineName/licenseProfiles/default?api-version=2023-10-03-preview"

    $body = @{
        location   = $Location
        properties = @{
            softwareAssurance = @{
                softwareAssuranceCustomer = $true
            }
        }
    } | ConvertTo-Json -Depth 3

    $bodyFile = Join-Path ([IO.Path]::GetTempPath()) "body_$([guid]::NewGuid().ToString('N')).json"

    try {
        Set-Content -Path $bodyFile -Value $body -Encoding UTF8 -Force

        for ($i = 1; $i -le $MaxRetries; $i++) {
            $out = az rest --method PUT --uri $uri --body "@$bodyFile" 2>&1

            if ($LASTEXITCODE -eq 0) { return "Success" }

            $errMsg = $out -join ' '
            if ($i -lt $MaxRetries) {
                Write-Log WARN "Attempt $i failed for '$MachineName': $errMsg — retrying in 10s..."
                Start-Sleep -Seconds 10
            }
        }
    }
    finally {
        if (Test-Path $bodyFile) { Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue }
    }

    Write-Log ERROR "Failed after $MaxRetries attempts: '$MachineName' (RG: $ResourceGroup) — $errMsg"
    return "Failure"
}

# =============================================================================
# PROCESS SUBSCRIPTION
# =============================================================================
function Invoke-Subscription {
    param (
        [string] $SubscriptionId,
        [string] $SubscriptionName,
        [hashtable] $Stats
    )

    Write-Log INFO "--- Subscription: $SubscriptionName ($SubscriptionId)"

    az account set --subscription $SubscriptionId 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Log WARN "Could not set context. Skipping."
        $Stats.Skipped++
        return
    }

    $machines = Get-TargetMachines -SubscriptionId $SubscriptionId

    if (-not $machines -or $machines.Count -eq 0) {
        Write-Log INFO "All machines activated (or none exist)."
        $Stats.Compliant++
        return
    }

    Write-Log INFO "Found $($machines.Count) machine(s) without Software Assurance benefits."

    foreach ($m in $machines) {
        Write-Log INFO "  -> $($m.machineName) | RG: $($m.resourceGroup) | OS: $($m.operatingSystem) | Location: $($m.location)"

        $result = Enable-SoftwareAssurance `
            -SubscriptionId $SubscriptionId `
            -ResourceGroup $m.resourceGroup `
            -MachineName $m.machineName `
            -Location $m.location

        if ($result -eq "Success") { $Stats.Success++ } else { $Stats.Failure++ }
        $Stats.Total++

        Write-Log RESULT "$($m.machineName),$($m.resourceGroup),$SubscriptionId,$($m.operatingSystem),$($m.location),$result"
    }
}

# =============================================================================
# MAIN
# =============================================================================
try {
    Write-Log INFO "=== Azure Arc Software Assurance Activation Runbook ==="

    Test-Prerequisites
    Connect-Azure
    Install-RequiredExtensions

    $subsJson = az account list --all --output json 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Failed to list subscriptions." }
    $subs = $subsJson | ConvertFrom-Json | Where-Object { $_.state -eq "Enabled" }

    Write-Log INFO "Found $($subs.Count) enabled subscription(s)."

    $stats = @{ Total = 0; Success = 0; Failure = 0; Compliant = 0; Skipped = 0 }

    Write-Log RESULT "MachineName,ResourceGroup,SubscriptionId,OperatingSystem,Location,UpdateResult"

    foreach ($sub in $subs) {
        Invoke-Subscription -SubscriptionId $sub.id -SubscriptionName $sub.name -Stats $stats
    }

    $subsProcessed = $subs.Count - $stats.Compliant - $stats.Skipped

    Write-Log INFO "=== SUMMARY ==="
    Write-Log INFO "Subscriptions: $($subs.Count) total | $subsProcessed with non-activated machines | $($stats.Compliant) fully activated | $($stats.Skipped) skipped"
    Write-Log INFO "Machines: $($stats.Total) processed | $($stats.Success) success | $($stats.Failure) failure"

    if ($stats.Failure -gt 0) {
        Write-Log WARN "$($stats.Failure) machine(s) failed — review RESULT lines above."
    }

    Write-Log INFO "=== Done ==="
}
catch {
    Write-Log FATAL "Execution failed: $($_.Exception.Message)"
    throw
}
