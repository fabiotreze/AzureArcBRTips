# =============================================================================
# DISCLAIMER:
#   This script is provided "AS IS" without warranty of any kind, express or
#   implied. Use at your own risk. Always test in a non-production environment
#   before deploying to production. The author is not responsible for any
#   damage or data loss caused by the use of this script.
#
#   Contributions and feedback are welcome via GitHub Issues and Pull Requests.
# =============================================================================

#Requires -Version 7.2

<#
.SYNOPSIS
    Activates Software Assurance benefits on Azure Arc Windows machines.

.DESCRIPTION
    Queries all subscriptions for Azure Arc Windows machines where Software Assurance
    benefits are not activated, and enables them via REST API.

    Modes:
    - Report: Lists machines without SA benefits — no changes applied.
    - Activate: Enables Software Assurance on eligible machines.

    Uses ONLY Azure CLI — no Az PowerShell modules required.

.PARAMETER Mode
    Operation mode. Activate (default for scheduled execution) applies changes;
    Report only lists.

.EXAMPLE
    .\AzArcEnableWindowsSA.ps1 -Mode Report

.EXAMPLE
    .\AzArcEnableWindowsSA.ps1 -Mode Activate

.EXAMPLE
    .\AzArcEnableWindowsSA.ps1 -Mode Activate -WhatIf

.NOTES
    Reference: https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-license-and-billing-for-extended-security-updates

.PREREQUISITES
    - PowerShell 7.2+ Runtime Environment
    - Azure CLI (pre-installed in Azure Automation)
    - Managed Identity with the following MINIMUM RBAC roles:
      1. Reader (subscription scope) - required for Azure Resource Graph queries
      2. Azure Connected Machine Resource Administrator (subscription or RG scope)
         - required for Microsoft.HybridCompute/machines/licenseProfiles/write
    - Assignment commands:
      az role assignment create --assignee <MI-ObjectId> --role 'Reader' --scope /subscriptions/<sub-id>
      az role assignment create --assignee <MI-ObjectId> --role 'Azure Connected Machine Resource Administrator' --scope /subscriptions/<sub-id>
#>

[CmdletBinding(PositionalBinding = $false, SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateSet('Report', 'Activate')]
    [string]$Mode = 'Activate'
)

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

function Format-CsvField {
    param([string]$Value)
    $field = if ($null -eq $Value) { '' } else { $Value }
    if ($field -match '[,"\r\n]') { return '"{0}"' -f $field.Replace('"', '""') }
    return $field
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
# =============================================================================
function Enable-SoftwareAssurance {
    param (
        [string] $SubscriptionId,
        [string] $ResourceGroup,
        [string] $MachineName,
        [string] $Location,
        [int]    $MaxRetries = 3
    )

    $transientPatterns = @('RequestTimeout', 'TooManyRequests', '429', '503', 'ServiceUnavailable', 'GatewayTimeout', 'ConnectionReset')

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
            $isTransient = $transientPatterns | Where-Object { $errMsg -match $_ }

            if (-not $isTransient) {
                Write-Log ERROR "Non-transient error for '$MachineName': $errMsg"
                return "Failure"
            }

            if ($i -lt $MaxRetries) {
                $delay = [math]::Pow(2, $i) * 5
                Write-Log WARN "Transient error (attempt $i/$MaxRetries) for '$MachineName' — retrying in ${delay}s..."
                Start-Sleep -Seconds $delay
            }
        }
    }
    finally {
        if (Test-Path $bodyFile) { Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue }
    }

    Write-Log ERROR "Exhausted $MaxRetries retries for '$MachineName' (RG: $ResourceGroup)."
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

        $csvFields = @($m.machineName, $m.resourceGroup, $SubscriptionId, $m.operatingSystem, $m.location) | ForEach-Object { Format-CsvField $_ }

        switch ($Mode) {
            'Report' {
                Write-Log RESULT (($csvFields + (Format-CsvField 'PendingActivation')) -join ',')
                $Stats.Total++
                continue
            }

            'Activate' {
                if (-not $PSCmdlet.ShouldProcess("$($m.machineName) (RG: $($m.resourceGroup))", "Enable Software Assurance")) {
                    continue
                }

                $result = Enable-SoftwareAssurance `
                    -SubscriptionId $SubscriptionId `
                    -ResourceGroup $m.resourceGroup `
                    -MachineName $m.machineName `
                    -Location $m.location

                if ($result -eq "Success") { $Stats.Success++ } else { $Stats.Failure++ }
                $Stats.Total++

                Write-Log RESULT (($csvFields + (Format-CsvField $result)) -join ',')
            }
        }
    }
}

# =============================================================================
# MAIN
# =============================================================================
try {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Log INFO "=== Azure Arc Software Assurance Activation Runbook ==="
    Write-Log INFO "Mode=$Mode"

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

    switch ($Mode) {
        'Report' {
            Write-Log INFO "Machines pending activation: $($stats.Total)"
        }
        'Activate' {
            Write-Log INFO "Machines: $($stats.Total) processed | $($stats.Success) success | $($stats.Failure) failure"
            if ($stats.Failure -gt 0) {
                Write-Log WARN "$($stats.Failure) machine(s) failed — review RESULT lines above."
            }
        }
    }

    $stopwatch.Stop()
    Write-Log INFO "Elapsed: $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))"
    Write-Log INFO "=== Done ==="
}
catch {
    Write-Log FATAL "Execution failed: $($_.Exception.Message)"
    throw
}
