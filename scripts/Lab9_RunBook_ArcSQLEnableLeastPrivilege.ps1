# =============================================================================
# DISCLAIMER:
#   This script is provided AS IS without warranty of any kind, express or
#   implied. Use at your own risk. Always test in a non-production environment
#   before deploying to production. The author is not responsible for any
#   damage or data loss caused by the use of this script.
#
#   Contributions and feedback are welcome via GitHub Issues and Pull Requests.
# =============================================================================

#Requires -Version 7.2

<#
.SYNOPSIS
    Enables LeastPrivilege FeatureFlag on Azure Arc machines with SQL Server extension.
.DESCRIPTION
    Queries all subscriptions for Azure Arc machines with WindowsAgent.SqlServer
    extension where LeastPrivilege feature flag is disabled or missing, and enables it.
    Modos de operacao:
    - Report: Lista maquinas sem LeastPrivilege — nenhuma alteracao e aplicada.
    - Enable: Habilita o FeatureFlag LeastPrivilege nas maquinas elegiveis.
    Uses ONLY Azure CLI — no Az PowerShell modules required.
.PARAMETER Mode
    Modo de operacao. Enable (default for scheduled execution) aplica alteracoes;
    Report apenas lista.
.EXAMPLE
    .\AzArcSQLEnableLeastPrivilege.ps1 -Mode Report
.EXAMPLE
    .\AzArcSQLEnableLeastPrivilege.ps1 -Mode Enable
.NOTES
    Reference: https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/configure-least-privilege

.PREREQUISITES
    - PowerShell 7.2+ Runtime Environment
    - Azure CLI (pre-installed in Azure Automation)
    - Managed Identity with the following MINIMUM RBAC roles:
      1. Reader (subscription scope) — required for Azure Resource Graph queries
      2. Azure Connected Machine Resource Administrator (subscription or resource group scope)
         — required for Microsoft.HybridCompute/machines/extensions/write
    - Assignment command:
      az role assignment create --assignee <MI-ObjectId> --role 'Reader' --scope /subscriptions/<sub-id>
      az role assignment create --assignee <MI-ObjectId> --role 'Azure Connected Machine Resource Administrator' --scope /subscriptions/<sub-id>
#>

[CmdletBinding(PositionalBinding = $false, SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateSet('Report', 'Enable')]
    [string]$Mode = 'Enable'
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
    foreach ($ext in @("resource-graph", "arcdata")) {
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
| where type == "microsoft.hybridcompute/machines/extensions"
| where name == "WindowsAgent.SqlServer"
| extend settings = parse_json(properties).settings
| where tostring(settings.SqlManagement.IsEnabled) == "true"
| extend machineName = tolower(extract("machines/([^/]+)/extensions", 1, id))
| where isnotempty(machineName)
| join kind=inner (
    resources
    | where type == "microsoft.hybridcompute/machines"
    | where tolower(tostring(properties.status)) == "connected"
    | project machineId = id,
             machineName = tolower(name),
             lastStatusChange = tostring(properties.lastStatusChange)
) on machineName
| extend ffLower = tolower(tostring(settings.FeatureFlags))
| where not(ffLower matches regex '("name":"leastprivilege"[^}]*"enable":(true|"true"))|("enable":(true|"true")[^}]*"name":"leastprivilege")')
| extend lpEnabled = iff(ffLower has "leastprivilege", "false", "notset")
| project machineName, resourceGroup, subscriptionId, lpEnabled, lastStatusChange, machineId
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
# ENABLE FEATURE FLAG
# =============================================================================
function Enable-LeastPrivilegeFlag {
    param (
        [string] $ResourceGroup,
        [string] $MachineName,
        [int]    $MaxRetries = 3
    )

    $transientPatterns = @('RequestTimeout', 'TooManyRequests', '429', '503', 'ServiceUnavailable', 'GatewayTimeout', 'ConnectionReset')

    for ($i = 1; $i -le $MaxRetries; $i++) {
        $out = az sql server-arc extension feature-flag set `
            --name LeastPrivilege --enable true `
            --resource-group $ResourceGroup --machine-name $MachineName 2>&1

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
        Write-Log INFO "All machines compliant (or none exist)."
        $Stats.Compliant++
        return
    }

    Write-Log INFO "Found $($machines.Count) non-compliant machine(s)."

    foreach ($m in $machines) {
        Write-Log INFO "  -> $($m.machineName) | RG: $($m.resourceGroup) | LP: $($m.lpEnabled)"

        $csvFields = @($m.machineName, $m.resourceGroup, $SubscriptionId, $m.lpEnabled) | ForEach-Object { Format-CsvField $_ }

        switch ($Mode) {
            'Report' {
                Write-Log RESULT (($csvFields + (Format-CsvField 'PendingEnable')) -join ',')
                $Stats.Total++
                continue
            }

            'Enable' {
                if (-not $PSCmdlet.ShouldProcess("$($m.machineName) (RG: $($m.resourceGroup))", "Enable LeastPrivilege FeatureFlag")) {
                    continue
                }

                $result = Enable-LeastPrivilegeFlag -ResourceGroup $m.resourceGroup -MachineName $m.machineName

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

    Write-Log INFO "=== Azure Arc SQL LeastPrivilege Runbook ==="
    Write-Log INFO "Mode=$Mode"

    Test-Prerequisites
    Connect-Azure
    Install-RequiredExtensions

    $subsJson = az account list --all --output json 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Failed to list subscriptions." }
    $subs = $subsJson | ConvertFrom-Json | Where-Object { $_.state -eq "Enabled" }

    Write-Log INFO "Found $($subs.Count) enabled subscription(s)."

    $stats = @{ Total = 0; Success = 0; Failure = 0; Compliant = 0; Skipped = 0 }

    Write-Log RESULT "MachineName,ResourceGroup,SubscriptionId,LPStatusBefore,UpdateResult"

    foreach ($sub in $subs) {
        Invoke-Subscription -SubscriptionId $sub.id -SubscriptionName $sub.name -Stats $stats
    }

    $subsProcessed = $subs.Count - $stats.Compliant - $stats.Skipped

    Write-Log INFO "=== SUMMARY ==="
    Write-Log INFO "Subscriptions: $($subs.Count) total | $subsProcessed with non-compliant machines | $($stats.Compliant) fully compliant | $($stats.Skipped) skipped"

    switch ($Mode) {
        'Report' {
            Write-Log INFO "Machines pending enable: $($stats.Total)"
        }
        'Enable' {
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
