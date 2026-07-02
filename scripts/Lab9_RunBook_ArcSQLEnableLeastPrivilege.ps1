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
    extension where LeastPrivilege is NOT EXPLICITLY enabled, and enables it.

    O runbook FORÇA o flag LeastPrivilege explicitamente em TODAS as máquinas SQL
    Arc Connected que não o declaram no FeatureFlags. Como isso ALTERA a settings
    da extensão, o RP re-executa o Enable e o deployer roda
    GrantLeastPrivilegePermissions(), que configura:
    - Conta de serviço: NT SERVICE\SqlServerExtension
    - Grupo local: Hybrid Agent Extension Applications
    - Permissões SQL mínimas (Connect SQL, View Server State, etc.)
    - Scheduled Task: SqlServerExtensionPermissionProvider

    Mesmo em versões >= 1.1.2504 (LP default-ON), forçar o flag explícito ACIONA o
    deployer para re-configurar a conta de serviço caso ela esteja como LocalSystem.

    NOTA: este runbook valida apenas o lado Azure (sucesso do 'feature-flag set').
    A troca efetiva da conta de serviço no SO deve ser confirmada no próprio nó
    (grupo local + logon da conta do serviço da extensão).

    Modos de operação:
    - Report: Lista máquinas não-compliant — nenhuma alteração é aplicada.
    - Enable: Habilita o FeatureFlag LeastPrivilege nas máquinas elegíveis.

    Uses ONLY Azure CLI — no Az PowerShell modules required.

.PARAMETER Mode
    Modo de operação. Report (default) apenas lista; Enable aplica alterações.

.EXAMPLE
    .\sql-least-privilege.ps1 -Mode Report

.EXAMPLE
    .\sql-least-privilege.ps1 -Mode Enable

.EXAMPLE
    .\sql-least-privilege.ps1 -Mode Enable -WhatIf

.NOTES
    Reference: https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/configure-least-privilege?view=sql-server-ver17

.PREREQUISITES
    - PowerShell 7.2+ Runtime Environment (confirme em Runbook > Runtime environment).
    - Azure CLI (pre-installed in Azure Automation).
    - Managed Identity com os papeis RBAC MINIMOS, em TODAS as assinaturas-alvo:
        1. Reader (escopo de assinatura) — necessario para Azure Resource Graph.
        2. Azure Connected Machine Resource Administrator (assinatura ou RG)
           — necessario para Microsoft.HybridCompute/machines/extensions/write.
      Comando de atribuicao:
        az role assignment create --assignee <MI-ObjectId> --role 'Reader' --scope /subscriptions/<sub-id>
        az role assignment create --assignee <MI-ObjectId> --role 'Azure Connected Machine Resource Administrator' --scope /subscriptions/<sub-id>

.PARAMETER ExtensionVersions
    Hashtable opcional para FIXAR a versao das extensoes do Azure CLI e evitar
    breaking changes (ex.: @{ arcdata = '1.5.13'; 'resource-graph' = '2.1.0' }).
    Sem valor, instala a versao mais recente.
#>

[CmdletBinding(PositionalBinding = $false, SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateSet('Report', 'Enable')]
    [string]$Mode = 'Report',

    [Parameter()]
    [hashtable]$ExtensionVersions = @{}
)

$ErrorActionPreference = "Stop"

# Padroes de erro transiente (retry com backoff) compartilhados entre ARG e enable.
$script:TransientPatterns = @('RequestTimeout', 'TooManyRequests', '429', '503', 'ServiceUnavailable', 'GatewayTimeout', 'ConnectionReset')

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
    param([hashtable] $Versions = @{})

    $installed = (az extension list --output json 2>$null | ConvertFrom-Json).name
    foreach ($ext in @("resource-graph", "arcdata")) {
        if ($ext -notin $installed) {
            $ver = $Versions[$ext]
            if ($ver) {
                Write-Log INFO "Installing extension '$ext' (version $ver)..."
                az extension add --name $ext --version $ver --yes 2>$null | Out-Null
            }
            else {
                Write-Log INFO "Installing extension '$ext' (latest)..."
                az extension add --name $ext --yes 2>$null | Out-Null
            }
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
# RESOURCE GRAPH QUERY (single call across all subscriptions, with retry)
# =============================================================================
function Get-TargetMachines {
    param ([string[]] $SubscriptionIds)

    $queryFile = Join-Path ([IO.Path]::GetTempPath()) "arg_$([guid]::NewGuid().ToString('N')).kql"

    $kql = @'
resources
| where type == "microsoft.hybridcompute/machines/extensions"
| where name == "WindowsAgent.SqlServer"
| extend settings = parse_json(properties).settings
| extend machineName = tolower(extract("machines/([^/]+)/extensions", 1, id))
| extend version = tostring(properties.typeHandlerVersion)
| where isnotempty(machineName)
| join kind=inner (
    resources
    | where type == "microsoft.hybridcompute/machines"
    | where tolower(tostring(properties.status)) == "connected"
    | project machineName = tolower(name)
) on machineName
| extend ffLower = tolower(tostring(settings.FeatureFlags))
// Considera LP explicitamente habilitado APENAS se o FeatureFlags contém "leastprivilege" com "true"
| extend lpExplicitlyEnabled = ffLower has "leastprivilege" and ffLower has "true"
// Retorna TODAS que NAO tem LP explicitamente habilitado — para forçar enable
| where not(lpExplicitlyEnabled)
| extend lpStatus = iff(ffLower has "leastprivilege", "ExplicitlyDisabled", "NotSet")
| project machineName, resourceGroup, subscriptionId, version, lpStatus
| where isnotempty(machineName) and isnotempty(resourceGroup)
'@

    $transientPatterns = $script:TransientPatterns

    try {
        Set-Content -Path $queryFile -Value $kql -Encoding UTF8 -Force

        $pageSize = 1000
        $skip = 0
        $maxRetries = 5
        $allData = [System.Collections.Generic.List[object]]::new()

        do {
            $page = $null
            for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
                $json = az graph query -q "@$queryFile" --subscriptions $SubscriptionIds `
                    --first $pageSize --skip $skip --output json 2>&1

                if ($LASTEXITCODE -eq 0) { $page = $json | ConvertFrom-Json; break }

                $errMsg = $json -join ' '
                $isTransient = $transientPatterns | Where-Object { $errMsg -match $_ }
                if (-not $isTransient -or $attempt -eq $maxRetries) {
                    throw "Resource Graph query failed: $errMsg"
                }

                $delay = [math]::Pow(2, $attempt) * 2
                Write-Log WARN "ARG transient error (attempt $attempt/$maxRetries) — retrying in ${delay}s..."
                Start-Sleep -Seconds $delay
            }

            $pageData = $page.data
            $pageCount = ($pageData | Measure-Object).Count

            if ($pageCount -gt 0) {
                $allData.AddRange([object[]]$pageData)
                $skip += $pageCount
                if ($skip -gt $pageSize) {
                    Write-Log INFO "Paginating Resource Graph: $($allData.Count) rows fetched so far..."
                }
            }
        } while ($pageCount -eq $pageSize)

        # Virgula evita o unrolling da List no return (lista vazia viraria $null).
        return , $allData
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

    for ($i = 1; $i -le $MaxRetries; $i++) {
        $out = az sql server-arc extension feature-flag set `
            --name LeastPrivilege --enable true `
            --resource-group $ResourceGroup --machine-name $MachineName 2>&1

        if ($LASTEXITCODE -eq 0) { return "Success" }

        $errMsg = $out -join ' '
        $isTransient = $script:TransientPatterns | Where-Object { $errMsg -match $_ }

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
# PROCESS MACHINES
# =============================================================================
function Invoke-Machines {
    param (
        [System.Collections.Generic.List[object]] $Machines,
        [hashtable] $Stats
    )

    $currentSub = $null

    foreach ($m in $Machines) {
        Write-Log INFO "  -> $($m.machineName) | Sub: $($m.subscriptionId) | RG: $($m.resourceGroup) | LP: $($m.lpStatus) | Ver: $($m.version)"

        $csvFields = @($m.machineName, $m.resourceGroup, $m.subscriptionId, $m.version, $m.lpStatus) | ForEach-Object { Format-CsvField $_ }

        if ($Mode -eq 'Report') {
            Write-Log RESULT (($csvFields + (Format-CsvField 'PendingEnable')) -join ',')
            $Stats.Total++
            continue
        }

        # --- Enable ---
        if (-not $PSCmdlet.ShouldProcess("$($m.machineName) (RG: $($m.resourceGroup))", "Enable LeastPrivilege FeatureFlag")) {
            continue
        }

        # Troca o contexto somente quando a assinatura muda (a query foi unica).
        if ($m.subscriptionId -ne $currentSub) {
            az account set --subscription $m.subscriptionId 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Log WARN "Could not set context for $($m.subscriptionId). Skipping $($m.machineName)."
                $Stats.Failure++; $Stats.Total++
                Write-Log RESULT (($csvFields + (Format-CsvField 'ContextError')) -join ',')
                continue
            }
            $currentSub = $m.subscriptionId
        }

        $result = Enable-LeastPrivilegeFlag -ResourceGroup $m.resourceGroup -MachineName $m.machineName

        if ($result -eq "Success") { $Stats.Success++ } else { $Stats.Failure++ }
        $Stats.Total++

        Write-Log RESULT (($csvFields + (Format-CsvField $result)) -join ',')
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
    Install-RequiredExtensions -Versions $ExtensionVersions

    $subsJson = az account list --all --output json 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Failed to list subscriptions." }
    $subs = $subsJson | ConvertFrom-Json | Where-Object { $_.state -eq "Enabled" }

    Write-Log INFO "Found $($subs.Count) enabled subscription(s)."

    $stats = @{ Total = 0; Success = 0; Failure = 0 }

    Write-Log INFO "Querying Resource Graph across all subscriptions..."
    $machines = Get-TargetMachines -SubscriptionIds $subs.id

    Write-Log RESULT "MachineName,ResourceGroup,SubscriptionId,Version,LPStatus,UpdateResult"

    if ($machines.Count -eq 0) {
        Write-Log INFO "All machines compliant (or none exist)."
    }
    else {
        $affectedSubs = ($machines.subscriptionId | Sort-Object -Unique | Measure-Object).Count
        Write-Log INFO "Found $($machines.Count) non-compliant machine(s) across $affectedSubs subscription(s)."
        Invoke-Machines -Machines $machines -Stats $stats
    }

    Write-Log INFO "=== SUMMARY ==="
    Write-Log INFO "Subscriptions scanned: $($subs.Count)"

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
