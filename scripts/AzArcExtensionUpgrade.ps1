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
    Gerencia atualizações de extensões em Azure Arc-enabled servers.

.DESCRIPTION
    Consulta todas as subscrições para máquinas Azure Arc conectadas e gerencia
    extensões instaladas usando Azure CLI.

    Modos de operação:
    - Report: Mostra extensões, versões atuais, versões mais recentes disponíveis
      e indica se há upgrade pendente. Nenhuma alteração é aplicada.
    - Upgrade: Atualiza extensões que possuem versão mais recente disponível via
      az connectedmachine upgrade-extension.
    - EnableAutoUpgrade: Habilita o flag enable-auto-upgrade nas extensões.
    - DisableAutoUpgrade: Desabilita o flag enable-auto-upgrade nas extensões.

    O script foi desenhado para Azure Automation com Managed Identity e também
    pode ser executado interativamente para validação.

.PARAMETER Mode
    Modo de operação. Report (default) apenas lista; os demais aplicam alterações.

.EXAMPLE
    .\AzArcExtensionUpgrade.ps1 -Mode Report

.EXAMPLE
    .\AzArcExtensionUpgrade.ps1 -Mode Upgrade

.EXAMPLE
    .\AzArcExtensionUpgrade.ps1 -Mode Upgrade -WhatIf

.EXAMPLE
    .\AzArcExtensionUpgrade.ps1 -Mode EnableAutoUpgrade

.NOTES
    KQL base para validação manual no Azure Resource Graph.

    resources
    | where type =~ 'microsoft.hybridcompute/machines'
    | where tostring(properties.status) =~ 'Connected'
    | project machineId = tolower(id), machineName = name, resourceGroup, subscriptionId, location,
              osType = tostring(properties.osType), status = tostring(properties.status)
    | join kind=inner (
        resources
        | where type =~ 'microsoft.hybridcompute/machines/extensions'
        | parse id with '/subscriptions/' extSubscriptionId '/resourceGroups/' extResourceGroup
                       '/providers/Microsoft.HybridCompute/machines/' extMachineName '/extensions/' extensionName
        | extend machineId = tolower(strcat('/subscriptions/', extSubscriptionId, '/resourceGroups/',
                                           extResourceGroup, '/providers/Microsoft.HybridCompute/machines/', extMachineName))
        | extend publisher = tostring(properties.publisher)
        | extend extensionType = tostring(properties.type)
        | extend currentVersion = tostring(properties.typeHandlerVersion)
        | extend provisioningState = tostring(properties.provisioningState)
        | extend enableAutoUpgrade = tostring(coalesce(properties.enableAutoUpgrade, properties.enableAutomaticUpgrade))
        | extend statusCode = tostring(properties.instanceView.status.code)
        | extend healthState = iff(provisioningState != 'Succeeded' or statusCode has_any ('error', 'fail'),
                                   'FailedOrNotHealthy', 'Healthy')
        | project machineId, extensionName, publisher, extensionType, currentVersion,
                  provisioningState, enableAutoUpgrade, healthState
    ) on machineId
    | project machineName, resourceGroup, subscriptionId, extensionName, publisher, extensionType,
              provisioningState, currentVersion, enableAutoUpgrade, healthState
    | order by machineName asc, extensionName asc

    Limitação do ARG — colunas que NÃO podem ser obtidas via query:
      - LatestVersion     → requer: az connectedmachine extension image list
      - UpgradeAvailable  → requer comparação CurrentVersion vs LatestVersion
    O script resolve isto automaticamente nos modos Report e Upgrade.

.PREREQUISITES
    - PowerShell 7.2+ Runtime Environment
    - Azure CLI (pre-installed in Azure Automation)
    - Managed Identity with the following MINIMUM RBAC roles:
      1. Reader (subscription scope) - required for Azure Resource Graph queries
      2. Azure Connected Machine Resource Administrator (subscription or RG scope)
         - required for Microsoft.HybridCompute/machines/extensions/read
         - required for Microsoft.HybridCompute/machines/extensions/write
         - required for Microsoft.HybridCompute/machines/upgradeExtensions/action
    - Assignment commands:
      az role assignment create --assignee <MI-ObjectId> --role 'Reader' --scope /subscriptions/<sub-id>
      az role assignment create --assignee <MI-ObjectId> --role 'Azure Connected Machine Resource Administrator' --scope /subscriptions/<sub-id>
#>

[CmdletBinding(PositionalBinding = $false, SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateSet('Report', 'Upgrade', 'EnableAutoUpgrade', 'DisableAutoUpgrade')]
    [string]$Mode = 'Upgrade'
)

$ErrorActionPreference = 'Stop'

# Cache de versões: chave = "location|publisher|extensionType" → valor = string da versão mais recente
$script:VersionCache = @{}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Write-Log {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR', 'FATAL', 'RESULT')]
        [string]$Level,
        [string]$Message
    )

    Write-Output ("[{0}][{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

function Format-CsvField {
    param([string]$Value)
    $field = if ($null -eq $Value) { '' } else { $Value }
    if ($field -match '[,"\r\n]') { return '"{0}"' -f $field.Replace('"', '""') }
    return $field
}

# ---------------------------------------------------------------------------
# Validação e setup
# ---------------------------------------------------------------------------

function Test-Prerequisites {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI not found.'
    }

    $version = (az version --output json 2>$null | ConvertFrom-Json).'azure-cli'
    Write-Log INFO ("Azure CLI {0} | PowerShell {1}" -f $version, $PSVersionTable.PSVersion)
}

function Install-RequiredExtensions {
    $installed = @((az extension list --output json 2>$null | ConvertFrom-Json).name)
    foreach ($extensionName in @('resource-graph', 'connectedmachine')) {
        if ($extensionName -notin $installed) {
            Write-Log INFO ("Installing extension '{0}'..." -f $extensionName)
            $output = az extension add --name $extensionName --yes 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw ("Failed to install extension '{0}': {1}" -f $extensionName, ($output -join ' '))
            }
        }
    }
}

function Connect-Azure {
    Write-Log INFO 'Authenticating with managed identity...'
    $output = az login --identity --allow-no-subscriptions 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("az login failed: {0}" -f ($output -join ' '))
    }

    Write-Log INFO 'Authenticated.'
}

# ---------------------------------------------------------------------------
# Azure Resource Graph — descoberta de máquinas e extensões
# ---------------------------------------------------------------------------

function Get-TargetExtensions {
    param([string[]]$SubscriptionIds)

    $queryFile = Join-Path ([IO.Path]::GetTempPath()) ("arg_arc_ext_{0}.kql" -f [guid]::NewGuid().ToString('N'))

    $kql = @"
resources
| where type =~ 'microsoft.hybridcompute/machines'
| where tostring(properties.status) =~ 'Connected'
| project machineId = tolower(id), machineName = name, resourceGroup, subscriptionId, location, osType = tostring(properties.osType), status = tostring(properties.status)
| join kind=inner (
    resources
    | where type =~ 'microsoft.hybridcompute/machines/extensions'
    | parse id with '/subscriptions/' extSubscriptionId '/resourceGroups/' extResourceGroup '/providers/Microsoft.HybridCompute/machines/' extMachineName '/extensions/' extensionName
    | extend machineId = tolower(strcat('/subscriptions/', extSubscriptionId, '/resourceGroups/', extResourceGroup, '/providers/Microsoft.HybridCompute/machines/', extMachineName))
    | extend publisher = tostring(properties.publisher)
    | extend extensionType = tostring(properties.type)
    | extend typeHandlerVersion = tostring(properties.typeHandlerVersion)
    | extend provisioningState = tostring(properties.provisioningState)
    | extend enableAutoUpgrade = tostring(coalesce(properties.enableAutoUpgrade, properties.enableAutomaticUpgrade))
    | extend autoUpgradeMinorVersion = tostring(properties.autoUpgradeMinorVersion)
    | extend statusCode = tostring(properties.instanceView.status.code)
    | extend statusMessage = tostring(properties.instanceView.status.message)
    | project machineId, extensionName, publisher, extensionType, typeHandlerVersion, provisioningState, enableAutoUpgrade, autoUpgradeMinorVersion, statusCode, statusMessage
) on machineId
| project machineName, resourceGroup, subscriptionId, location, osType, status, extensionName, publisher, extensionType, typeHandlerVersion, provisioningState, enableAutoUpgrade, autoUpgradeMinorVersion, statusCode, statusMessage
| order by machineName asc, extensionName asc
"@

    try {
        Set-Content -Path $queryFile -Value $kql -Encoding UTF8 -Force

        $pageSize = 1000
        $skip = 0
        $allData = [System.Collections.Generic.List[psobject]]::new()

        do {
            $json = az graph query -q "@$queryFile" --subscriptions @SubscriptionIds --first $pageSize --skip $skip --output json 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw ("Resource Graph query failed: {0}" -f ($json -join ' '))
            }

            $result = $json | ConvertFrom-Json
            $pageData = if ($null -eq $result.data) { @() } else { @($result.data) }
            $pageCount = $pageData.Count

            if ($pageCount -gt 0) {
                $allData.AddRange([psobject[]]$pageData)
                $skip += $pageCount
            }

            if ($skip -gt $pageSize) {
                Write-Log INFO ("Paginating Resource Graph: {0} rows fetched so far..." -f $allData.Count)
            }
        } while ($pageCount -eq $pageSize)

        return , $allData.ToArray()
    }
    finally {
        if (Test-Path $queryFile) {
            Remove-Item $queryFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Verificação de versão de extensões
# ---------------------------------------------------------------------------

function Get-LatestExtensionVersion {
    param(
        [string]$SubscriptionId,
        [string]$Location,
        [string]$Publisher,
        [string]$ExtensionType
    )

    $cacheKey = ("{0}|{1}|{2}" -f $Location, $Publisher, $ExtensionType).ToLower()
    if ($script:VersionCache.ContainsKey($cacheKey)) {
        return $script:VersionCache[$cacheKey]
    }

    $json = az connectedmachine extension image list `
        --subscription $SubscriptionId `
        --location $Location `
        --publisher $Publisher `
        --type $ExtensionType `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Log WARN ("Could not query extension images for {0}/{1} in {2}" -f $Publisher, $ExtensionType, $Location)
        $script:VersionCache[$cacheKey] = $null
        return $null
    }

    $images = $json | ConvertFrom-Json
    if (-not $images -or @($images).Count -eq 0) {
        $script:VersionCache[$cacheKey] = $null
        return $null
    }

    $versions = @($images | ForEach-Object {
        $v = if ($_.version) { $_.version } elseif ($_.name) { $_.name } else { $null }
        if ($v) { try { [System.Version]$v } catch { $null } } else { $null }
    } | Where-Object { $null -ne $_ })

    $latest = $versions | Sort-Object -Descending | Select-Object -First 1
    $result = if ($latest) { $latest.ToString() } else { $null }
    $script:VersionCache[$cacheKey] = $result
    return $result
}

function Test-UpgradeAvailable {
    param(
        [string]$CurrentVersion,
        [string]$LatestVersion
    )

    if ([string]::IsNullOrWhiteSpace($CurrentVersion) -or [string]::IsNullOrWhiteSpace($LatestVersion)) {
        return $false
    }

    try {
        return ([System.Version]$LatestVersion) -gt ([System.Version]$CurrentVersion)
    }
    catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# Ações de modificação — Upgrade e Auto-Upgrade
# ---------------------------------------------------------------------------

function Invoke-MachineExtensionUpgrade {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$MachineName,
        [Parameter(Mandatory)][hashtable]$ExtensionTargets,
        [int]$MaxRetries = 3
    )

    $transientPatterns = @('RequestTimeout', 'TooManyRequests', '429', '503', 'ServiceUnavailable', 'GatewayTimeout', 'ConnectionReset')

    # Monta JSON para --extension-targets: {"Publisher.Type": {"targetVersion": "x.y.z"}}
    $targetEntries = $ExtensionTargets.GetEnumerator() | ForEach-Object {
        '"{0}":{{"targetVersion":"{1}"}}' -f $_.Key, $_.Value
    }
    $targetsJson = '{' + ($targetEntries -join ',') + '}'

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $output = az connectedmachine upgrade-extension `
            --subscription $SubscriptionId `
            --resource-group $ResourceGroup `
            --machine-name $MachineName `
            --extension-targets $targetsJson `
            --no-wait 2>&1

        if ($LASTEXITCODE -eq 0) {
            return 'Success'
        }

        $errorText = $output -join ' '
        $isTransient = $transientPatterns | Where-Object { $errorText -match $_ }

        if (-not $isTransient) {
            Write-Log ERROR ("Non-transient error upgrading {0}: {1}" -f $MachineName, $errorText)
            return 'Failure'
        }

        if ($attempt -lt $MaxRetries) {
            $delay = [math]::Pow(2, $attempt) * 5   # 10s, 20s, 40s
            Write-Log WARN ("Transient error (attempt {0}/{1}) upgrading {2} — retrying in {3}s..." -f $attempt, $MaxRetries, $MachineName, $delay)
            Start-Sleep -Seconds $delay
        }
    }

    Write-Log ERROR ("Exhausted {0} retries upgrading {1}." -f $MaxRetries, $MachineName)
    return 'Failure'
}

function Set-ExtensionAutoUpgrade {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$MachineName,
        [Parameter(Mandatory)][string]$ExtensionName,
        [Parameter(Mandatory)][bool]$EnableAutoUpgrade,
        [int]$MaxRetries = 3
    )

    $transientPatterns = @('RequestTimeout', 'TooManyRequests', '429', '503', 'ServiceUnavailable', 'GatewayTimeout', 'ConnectionReset')
    $autoUpgradeValue = $EnableAutoUpgrade.ToString().ToLower()

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $output = az connectedmachine extension update `
            --subscription $SubscriptionId `
            --resource-group $ResourceGroup `
            --machine-name $MachineName `
            --name $ExtensionName `
            --enable-auto-upgrade $autoUpgradeValue `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            return 'Success'
        }

        $errorText = $output -join ' '
        $isTransient = $transientPatterns | Where-Object { $errorText -match $_ }

        if (-not $isTransient) {
            Write-Log ERROR ("Non-transient error for {0}/{1}: {2}" -f $MachineName, $ExtensionName, $errorText)
            return 'Failure'
        }

        if ($attempt -lt $MaxRetries) {
            $delay = [math]::Pow(2, $attempt) * 5
            Write-Log WARN ("Transient error (attempt {0}/{1}) for {2}/{3} — retrying in {4}s..." -f $attempt, $MaxRetries, $MachineName, $ExtensionName, $delay)
            Start-Sleep -Seconds $delay
        }
    }

    Write-Log ERROR ("Exhausted {0} retries for {1}/{2}." -f $MaxRetries, $MachineName, $ExtensionName)
    return 'Failure'
}

# ---------------------------------------------------------------------------
# Avaliação de saúde
# ---------------------------------------------------------------------------

function Get-ExtensionHealthState {
    param([psobject]$Extension)

    if ($Extension.provisioningState -and $Extension.provisioningState -ne 'Succeeded') {
        return 'FailedOrNotHealthy'
    }

    if ($Extension.statusCode -and $Extension.statusCode -match 'error|fail') {
        return 'FailedOrNotHealthy'
    }

    return 'Healthy'
}

# ---------------------------------------------------------------------------
# Processamento principal
# ---------------------------------------------------------------------------

function Invoke-Targets {
    param(
        [psobject[]]$Targets,
        [hashtable]$Stats
    )

    if (-not $Targets -or $Targets.Count -eq 0) {
        Write-Log INFO 'No connected Arc machines with extensions found.'
        return
    }

    Write-Log INFO ("Found {0} extension record(s) in scope." -f $Targets.Count)

    $isVersionMode = $Mode -in @('Report', 'Upgrade')

    # Para o modo Upgrade: coleta upgrades por máquina para executar em batch
    $machineUpgrades = [ordered]@{}

    if ($isVersionMode) {
        # Usa o primeiro subscription disponível para consultar imagens de extensão
        $firstSubscriptionId = ($Targets | Select-Object -First 1).subscriptionId

        # Pré-carrega versões para cada combinação única (location, publisher, extensionType)
        $uniqueCombos = $Targets | ForEach-Object {
            "{0}|{1}|{2}" -f $_.location, $_.publisher, $_.extensionType
        } | Select-Object -Unique

        Write-Log INFO ("Querying latest versions for {0} unique extension type(s)..." -f @($uniqueCombos).Count)

        foreach ($combo in $uniqueCombos) {
            $parts = $combo -split '\|'
            $null = Get-LatestExtensionVersion -SubscriptionId $firstSubscriptionId -Location $parts[0] -Publisher $parts[1] -ExtensionType $parts[2]
        }
    }

    # --- Relatório e coleta de extensões a atualizar ---
    foreach ($target in $Targets) {
        if ($null -eq $target) { continue }

        $healthState = Get-ExtensionHealthState -Extension $target
        $currentAutoUpgrade = if ($null -eq $target.enableAutoUpgrade -or [string]::IsNullOrWhiteSpace([string]$target.enableAutoUpgrade)) { 'Unknown' } else { [string]$target.enableAutoUpgrade }
        $currentVersion = if ($target.typeHandlerVersion) { [string]$target.typeHandlerVersion } else { 'Unknown' }

        $latestVersion = 'N/A'
        $upgradeAvailable = $false

        if ($isVersionMode) {
            $latest = Get-LatestExtensionVersion -SubscriptionId $target.subscriptionId -Location $target.location -Publisher $target.publisher -ExtensionType $target.extensionType
            $latestVersion = if ($latest) { $latest } else { 'N/A' }
            $upgradeAvailable = Test-UpgradeAvailable -CurrentVersion $currentVersion -LatestVersion $latestVersion
        }

        # --- CSV output ---
        if ($isVersionMode) {
            $csvFields = @($target.machineName, $target.resourceGroup, $target.subscriptionId,
                $target.extensionName, $target.publisher, $target.extensionType, $target.provisioningState,
                $currentVersion, $latestVersion, $upgradeAvailable, $currentAutoUpgrade, $healthState
            ) | ForEach-Object { Format-CsvField $_ }
        }
        else {
            $csvFields = @($target.machineName, $target.resourceGroup, $target.subscriptionId,
                $target.extensionName, $target.publisher, $target.extensionType, $target.provisioningState,
                $currentAutoUpgrade, $healthState
            ) | ForEach-Object { Format-CsvField $_ }
        }
        Write-Log RESULT ($csvFields -join ',')

        # --- Ação por modo ---
        switch ($Mode) {
            'Report' {
                if ($upgradeAvailable) { $Stats.UpgradesAvailable++ }
                continue
            }

            'Upgrade' {
                if ($healthState -eq 'FailedOrNotHealthy') {
                    $Stats.SkippedUnhealthy++
                    Write-Log WARN ("Skipping unhealthy extension: {0}/{1} | ProvisioningState={2} | StatusCode={3}" -f $target.machineName, $target.extensionName, $target.provisioningState, $target.statusCode)
                    continue
                }

                if (-not $upgradeAvailable) {
                    $Stats.AlreadyCurrent++
                    continue
                }

                # Agrupa extensões por máquina para upgrade em batch
                $machineKey = "{0}|{1}|{2}" -f $target.subscriptionId, $target.resourceGroup, $target.machineName
                if (-not $machineUpgrades.Contains($machineKey)) {
                    $machineUpgrades[$machineKey] = @{
                        SubscriptionId = $target.subscriptionId
                        ResourceGroup  = $target.resourceGroup
                        MachineName    = $target.machineName
                        Extensions     = [ordered]@{}
                    }
                }

                $extKey = "{0}.{1}" -f $target.publisher, $target.extensionType
                $machineUpgrades[$machineKey].Extensions[$extKey] = $latestVersion

                $Stats.UpgradesAvailable++
                Write-Log INFO ("Upgrade queued: {0}/{1} — {2} -> {3}" -f $target.machineName, $target.extensionName, $currentVersion, $latestVersion)
            }

            { $_ -in @('EnableAutoUpgrade', 'DisableAutoUpgrade') } {
                if ($healthState -eq 'FailedOrNotHealthy') {
                    $Stats.SkippedUnhealthy++
                    Write-Log WARN ("Extension in unhealthy state: {0}/{1} | ProvisioningState={2} | StatusCode={3}" -f $target.machineName, $target.extensionName, $target.provisioningState, $target.statusCode)
                    continue
                }

                $desiredState = ($Mode -eq 'EnableAutoUpgrade')
                $currentState = $null
                if ($currentAutoUpgrade -in @('true', 'false')) {
                    $currentState = [bool]::Parse($currentAutoUpgrade)
                }

                if ($null -ne $currentState -and $currentState -eq $desiredState) {
                    $Stats.AlreadyDesired++
                    continue
                }

                if (-not $PSCmdlet.ShouldProcess("$($target.machineName)/$($target.extensionName)", "Set EnableAutoUpgrade=$desiredState")) {
                    continue
                }

                $result = Set-ExtensionAutoUpgrade -SubscriptionId $target.subscriptionId -ResourceGroup $target.resourceGroup -MachineName $target.machineName -ExtensionName $target.extensionName -EnableAutoUpgrade:$desiredState
                $Stats.Total++

                if ($result -eq 'Success') { $Stats.Success++ }
                else { $Stats.Failure++ }
            }
        }
    }

    # --- Executa upgrades agrupados por máquina ---
    if ($Mode -eq 'Upgrade' -and $machineUpgrades.Count -gt 0) {
        Write-Log INFO ("=== Executing upgrades on {0} machine(s) ===" -f $machineUpgrades.Count)

        foreach ($entry in $machineUpgrades.Values) {
            $extList = ($entry.Extensions.GetEnumerator() | ForEach-Object { "{0} -> {1}" -f $_.Key, $_.Value }) -join ', '

            if (-not $PSCmdlet.ShouldProcess("$($entry.MachineName) [$extList]", "Upgrade extensions")) {
                continue
            }

            Write-Log INFO ("Upgrading {0}: {1}" -f $entry.MachineName, $extList)

            $result = Invoke-MachineExtensionUpgrade `
                -SubscriptionId $entry.SubscriptionId `
                -ResourceGroup $entry.ResourceGroup `
                -MachineName $entry.MachineName `
                -ExtensionTargets $entry.Extensions

            $Stats.MachinesProcessed++

            if ($result -eq 'Success') {
                $Stats.MachinesSuccess++
                $Stats.ExtensionsUpgraded += $entry.Extensions.Count
                Write-Log INFO ("Upgrade request sent for {0} ({1} extension(s))." -f $entry.MachineName, $entry.Extensions.Count)
            }
            else {
                $Stats.MachinesFailure++
                Write-Log ERROR ("Upgrade failed for {0}." -f $entry.MachineName)
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

try {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Log INFO '=== Azure Arc Extension Upgrade Runbook ==='
    Write-Log INFO ("Mode={0}" -f $Mode)

    Test-Prerequisites
    Connect-Azure
    Install-RequiredExtensions

    $subscriptionsJson = az account list --all --output json 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to list subscriptions.'
    }

    $subscriptions = $subscriptionsJson | ConvertFrom-Json | Where-Object { $_.state -eq 'Enabled' }
    $subscriptionIds = @($subscriptions | ForEach-Object { $_.id })
    Write-Log INFO ("Found {0} enabled subscription(s)." -f $subscriptionIds.Count)

    # Contadores unificados — cada modo usa os que precisa
    $stats = @{
        # Report / Upgrade
        UpgradesAvailable  = 0
        AlreadyCurrent     = 0
        # Upgrade
        MachinesProcessed  = 0
        MachinesSuccess    = 0
        MachinesFailure    = 0
        ExtensionsUpgraded = 0
        # EnableAutoUpgrade / DisableAutoUpgrade
        Total              = 0
        Success            = 0
        Failure            = 0
        AlreadyDesired     = 0
        # Compartilhado
        SkippedUnhealthy   = 0
    }

    # Cabeçalho CSV conforme modo
    if ($Mode -in @('Report', 'Upgrade')) {
        Write-Log RESULT 'MachineName,ResourceGroup,SubscriptionId,ExtensionName,Publisher,ExtensionType,ProvisioningState,CurrentVersion,LatestVersion,UpgradeAvailable,EnableAutoUpgrade,HealthState'
    }
    else {
        Write-Log RESULT 'MachineName,ResourceGroup,SubscriptionId,ExtensionName,Publisher,ExtensionType,ProvisioningState,EnableAutoUpgrade,HealthState'
    }

    $targets = Get-TargetExtensions -SubscriptionIds $subscriptionIds
    Invoke-Targets -Targets $targets -Stats $stats

    Write-Log INFO '=== SUMMARY ==='

    switch ($Mode) {
        'Report' {
            Write-Log INFO ("Extensions in scope: {0} | Upgrades available: {1} | Unhealthy (skipped): {2}" -f @($targets).Count, $stats.UpgradesAvailable, $stats.SkippedUnhealthy)
        }
        'Upgrade' {
            Write-Log INFO ("Upgrades available: {0} | Already current: {1} | Unhealthy (skipped): {2}" -f $stats.UpgradesAvailable, $stats.AlreadyCurrent, $stats.SkippedUnhealthy)
            Write-Log INFO ("Machines processed: {0} | Success: {1} | Failure: {2} | Extensions upgraded: {3}" -f $stats.MachinesProcessed, $stats.MachinesSuccess, $stats.MachinesFailure, $stats.ExtensionsUpgraded)
        }
        { $_ -in @('EnableAutoUpgrade', 'DisableAutoUpgrade') } {
            Write-Log INFO ("Extensions changed: {0} | Success: {1} | Failure: {2}" -f $stats.Total, $stats.Success, $stats.Failure)
            Write-Log INFO ("AlreadyDesired: {0} | Unhealthy (skipped): {1}" -f $stats.AlreadyDesired, $stats.SkippedUnhealthy)
        }
    }

    $stopwatch.Stop()
    Write-Log INFO ("Elapsed: {0}" -f $stopwatch.Elapsed.ToString('hh\:mm\:ss'))
    Write-Log INFO '=== Done ==='
}
catch {
    Write-Log FATAL ("Execution failed: {0}" -f $_.Exception.Message)
    throw
}
