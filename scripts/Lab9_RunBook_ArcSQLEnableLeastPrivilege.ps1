<#
.SYNOPSIS
    Enables LeastPrivilege FeatureFlag on Azure Arc machines with SQL Server extension.

.DESCRIPTION
    Queries all subscriptions for Azure Arc machines with WindowsAgent.SqlServer
    extension where LeastPrivilege feature flag is disabled or missing, and enables it.

    Uses ONLY Azure CLI — no Az PowerShell modules required.

.NOTES
    Reference: https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/configure-least-privilege?view=sql-server-ver17

.PREREQUISITES
    - PowerShell 7.2+ Runtime Environment
    - Azure CLI (pre-installed in Azure Automation)
    - Managed Identity with permissions on Azure Arc machines
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

    # KQL: Find Arc machines where LeastPrivilege is NOT enabled
    # Uses string match on serialized FeatureFlags — no mv-expand needed
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
# Ref: https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/configure-least-privilege
# =============================================================================
function Enable-LeastPrivilegeFlag {
    param (
        [string] $ResourceGroup,
        [string] $MachineName,
        [int]    $MaxRetries = 2
    )

    for ($i = 1; $i -le $MaxRetries; $i++) {
        $out = az sql server-arc extension feature-flag set `
            --name LeastPrivilege --enable true `
            --resource-group $ResourceGroup --machine-name $MachineName 2>&1

        if ($LASTEXITCODE -eq 0) { return "Success" }

        $errMsg = $out -join ' '
        if ($i -lt $MaxRetries) {
            Write-Log WARN "Attempt $i failed for '$MachineName': $errMsg — retrying in 10s..."
            Start-Sleep -Seconds 10
        }
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
        Write-Log INFO "All machines compliant (or none exist)."
        $Stats.Compliant++
        return
    }

    Write-Log INFO "Found $($machines.Count) non-compliant machine(s)."

    foreach ($m in $machines) {
        Write-Log INFO "  -> $($m.machineName) | RG: $($m.resourceGroup) | LP: $($m.lpEnabled)"

        $result = Enable-LeastPrivilegeFlag -ResourceGroup $m.resourceGroup -MachineName $m.machineName

        if ($result -eq "Success") { $Stats.Success++ } else { $Stats.Failure++ }
        $Stats.Total++

        Write-Log RESULT "$($m.machineName),$($m.resourceGroup),$SubscriptionId,$($m.lpEnabled),$result"
    }
}

# =============================================================================
# MAIN
# =============================================================================
try {
    Write-Log INFO "=== Azure Arc SQL LeastPrivilege Runbook ==="

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
