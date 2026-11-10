#Requires -Version 7.0
<#
.SYNOPSIS
  Read-only snapshot of SQL Server enabled by Azure Arc, to compare BEFORE and AFTER a PAYG change.
  Snapshot somente leitura do SQL Server habilitado pelo Azure Arc, para comparar ANTES e DEPOIS de uma mudanca PAYG.

.DESCRIPTION
  Reads Azure Resource Graph only (machines, SQL extension, SQL instances, SQLServerLicense). Changes nothing.
  One row per host ID that has SQL instance resources, with:
    Scenario  DirectPAYG           extension LicenseType = PAYG and no physical core license applied
              PhysicalCoreLicense  UsePhysicalCoreLicense applied (physical core license / unlimited virtualization)
              NotPAYG              Paid, LicenseOnly or not reported
              Unknown              no Arc machine or no SQL extension visible in ARG
    Check     OK or ATTENTION, with Findings codes (see below)
  Findings (ATTENTION): NO_MACHINE, ARC_NOT_CONNECTED, EXT_MISSING, EXT_NOT_SUCCEEDED, ESU_MISSING,
                        PCORE_NO_LICENSE_VISIBLE, PCORE_PLAN_MISMATCH
  Findings (INFO):      SQL_NOT_DISCOVERED, FREE_EDITIONS_ONLY, CONSENT_NOT_REPORTED
  Core values are estimates (same rules as the PAYG workbook), not billing.

  Run it once BEFORE the change (-Label Before) and once AFTER (-Label After), then use Compare-ArcSqlPaygSnapshot.ps1.
  The CSV can contain subscription IDs and host names: keep it out of the repository (it is git-ignored by default path).

.EXAMPLE
  ./Export-ArcSqlPaygSnapshot.ps1 -Label Before
  ./Export-ArcSqlPaygSnapshot.ps1 -Label After -Subscriptions <subscription-id>
#>
[CmdletBinding()]
param(
  [string]$Label = 'snapshot',
  [string]$OutDir = (Join-Path (Get-Location) 'arc-payg-snapshots'),
  [string[]]$Subscriptions
)

$ErrorActionPreference = 'Stop'

$script:Queries = [ordered]@{
  Instances = @"
resources
| where type =~ 'microsoft.azurearcdata/sqlserverinstances'
| project HostId=tolower(tostring(properties.containerResourceId)), Edition=tostring(properties.edition), Version=tostring(properties.version), InstanceLicenseType=tostring(properties.licenseType), LastInstanceInventory=tostring(properties.lastInventoryUploadTime)
"@
  Machines = @"
resources
| where type =~ 'microsoft.hybridcompute/machines'
| project HostId=tolower(id), MachineName=name, SubscriptionId=subscriptionId, ResourceGroup=resourceGroup, ArcStatus=tostring(properties.status), OsType=tostring(properties.osType), SqlDiscovered=tostring(properties.detectedProperties.mssqldiscovered), LogicalCores=toint(properties.detectedProperties.logicalCoreCount), PhysicalCores=toint(properties.detectedProperties.coreCount), Manufacturer=tostring(properties.detectedProperties.manufacturer), Model=tostring(properties.detectedProperties.model)
"@
  Extensions = @"
resources
| where type =~ 'microsoft.hybridcompute/machines/extensions'
| where tostring(properties.publisher) =~ 'Microsoft.AzureData'
| where tostring(properties.type) in~ ('WindowsAgent.SqlServer','LinuxAgent.SqlServer')
| project HostId=tolower(substring(id, 0, indexof(tolower(id), '/extensions'))), ExtensionState=tostring(properties.provisioningState), ExtensionVersion=tostring(properties.typeHandlerVersion), LicenseType=tostring(properties.settings.LicenseType), UsePcore=tostring(properties.settings.UsePhysicalCoreLicense.IsApplied), EnableESU=tostring(properties.settings.enableExtendedSecurityUpdates), Consent=tostring(properties.settings.ConsentToRecurringPAYG.Consented)
"@
  Licenses = @"
resources
| where type =~ 'microsoft.azurearcdata/sqlserverlicenses'
| project LicenseSubscriptionId=subscriptionId, BillingPlan=tostring(properties.billingPlan), ActivationState=tostring(properties.activationState), ScopeType=tostring(properties.scopeType), LicenseCores=toint(properties.physicalCores)
"@
}

function Invoke-ArgPaged {
  param([string]$Query, [string[]]$Subs)
  $all = [System.Collections.Generic.List[object]]::new(); $skip = $null; $seen = @{}
  do {
    $options = @{ '$top' = 1000; resultFormat = 'objectArray' }
    if ($skip) { $options.'$skipToken' = $skip }
    $request = @{ query = $Query; options = $options; subscriptions = @($Subs) }
    $attempt = 0
    while ($true) {
      $response = Invoke-AzRestMethod -Method POST -Path '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Payload ($request | ConvertTo-Json -Depth 10) -ErrorAction Stop
      if ($response.StatusCode -eq 429 -and $attempt -lt 5) { $attempt++; Start-Sleep -Seconds ([math]::Min(30, [math]::Pow(2, $attempt))); continue }
      break
    }
    if ($response.StatusCode -ne 200) { throw "ARG HTTP $($response.StatusCode): $($response.Content)" }
    $r = $response.Content | ConvertFrom-Json -Depth 100
    if ($null -eq $r.data) { throw 'ARG response has no data.' }
    foreach ($row in @($r.data)) { $all.Add($row) }
    $skip = [string]$r.'$skipToken'
    if ($skip) {
      if ($seen.ContainsKey($skip)) { throw 'ARG returned a repeated continuation token.' }
      $seen[$skip] = $true
    }
  } while ($skip)
  , @($all)
}

function ConvertTo-VersionMajor {
  param([string]$Version)
  switch -Regex ($Version) {
    'SQL Server 2014|^12\.' { 'SQL Server 2014'; break }
    'SQL Server 2016|^13\.' { 'SQL Server 2016'; break }
    'SQL Server 2017|^14\.' { 'SQL Server 2017'; break }
    'SQL Server 2019|^15\.' { 'SQL Server 2019'; break }
    'SQL Server 2022|^16\.' { 'SQL Server 2022'; break }
    'SQL Server 2025|^17\.' { 'SQL Server 2025'; break }
    default { if ($Version) { $Version } else { 'Not identified' } }
  }
}

function Get-EditionRank {
  param([string]$Edition)
  if ($Edition -match 'Enterprise') { 6 } elseif ($Edition -match 'Standard') { 5 } elseif ($Edition -match 'Web') { 4 }
  elseif ($Edition -match 'Express') { 3 } elseif ($Edition -match 'Developer') { 2 } elseif ($Edition -match 'Evaluation') { 1 } else { 0 }
}

function New-HostRecords {
  param($Instances, $Machines, $Extensions, $Licenses, [string]$SnapshotLabel, [string]$CapturedAt)

  $machineBy = @{}; foreach ($m in $Machines) { $machineBy[[string]$m.HostId] = $m }
  $extBy = @{}; foreach ($e in $Extensions) { $extBy[[string]$e.HostId] = $e }
  $groups = $Instances | Where-Object { ([string]$_.HostId) -like '*/providers/microsoft.hybridcompute/machines/*' } | Group-Object { [string]$_.HostId }

  foreach ($g in $groups) {
    $hostId = $g.Name
    $m = $machineBy[$hostId]; $x = $extBy[$hostId]
    $editions = @($g.Group | ForEach-Object { [string]$_.Edition } | Sort-Object -Unique)
    $versions = @($g.Group | ForEach-Object { ConvertTo-VersionMajor ([string]$_.Version) } | Sort-Object -Unique)
    $topRank = ($g.Group | ForEach-Object { Get-EditionRank ([string]$_.Edition) } | Measure-Object -Maximum).Maximum
    $topEdition = switch ($topRank) { 6 { 'Enterprise' } 5 { 'Standard' } 4 { 'Web' } 3 { 'Express' } 2 { 'Developer' } 1 { 'Evaluation' } default { 'Not identified' } }
    $hadr = @($g.Group | Where-Object { ([string]$_.InstanceLicenseType) -eq 'HADR' }).Count
    $active = $g.Count - $hadr
    $freeOnly = @($g.Group | Where-Object { ([string]$_.Edition) -notmatch 'Developer|Evaluation|Express' }).Count -eq 0
    $esuVersion = @($versions | Where-Object { $_ -in 'SQL Server 2014', 'SQL Server 2016' }).Count -gt 0
    $lastInv = ($g.Group | ForEach-Object { [string]$_.LastInstanceInventory } | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1)

    $arcStatus = if ($m) { [string]$m.ArcStatus } else { '' }
    $licenseType = if ($x -and [string]$x.LicenseType) { [string]$x.LicenseType } else { 'Not reported' }
    $pcore = [bool]($x -and ([string]$x.UsePcore) -eq 'true')
    $extState = if ($x) { [string]$x.ExtensionState } else { '' }
    $hostSub = if ($m) { [string]$m.SubscriptionId } else { ($hostId -split '/')[2] }

    # Core estimate: same rules as the workbook (not billing).
    $hw = ("$($m.Model) $($m.Manufacturer)").ToLowerInvariant()
    $isVm = $hw -match 'virtual|vmware|kvm|hvm|standard pc|google|nutanix|openstack|amazon|bhyve|xen|qemu|innotek|red hat'
    $physicalForm = (-not $isVm) -and $m -and [string]$m.Model -and [string]$m.Manufacturer
    $logical = if ($m -and $null -ne $m.LogicalCores) { [int]$m.LogicalCores } else { $null }
    $physical = if ($m -and $null -ne $m.PhysicalCores) { [int]$m.PhysicalCores } else { $null }
    $raw = if ($physicalForm) { if ($null -ne $physical) { $physical } else { $logical } } else { if ($null -ne $logical) { $logical } else { $physical } }
    $hostIsLinux = $m -and ([string]$m.OsType) -eq 'linux'
    $stdLimit = if ($topEdition -eq 'Standard') { if ($versions -contains 'SQL Server 2025') { 32 } else { 24 } } else { 0 }
    $cores = $null
    if ($topEdition -in 'Express', 'Developer', 'Evaluation' -or ($active -eq 0 -and -not $hostIsLinux)) { $cores = 0 }
    elseif ($topEdition -eq 'Not identified' -or $null -eq $raw -or $raw -le 0) { $cores = $null }
    elseif ($topEdition -eq 'Standard') { $cores = [math]::Max(4, [math]::Min($raw, $stdLimit)) }
    else { $cores = [math]::Max(4, $raw) }

    # Physical core license candidates: same subscription, or tenant scope.
    $cand = @($Licenses | Where-Object { ([string]$_.ActivationState) -in 'Active', 'Activated' -and (([string]$_.LicenseSubscriptionId) -eq $hostSub -or ([string]$_.ScopeType) -eq 'Tenant') })
    $plans = @($cand | ForEach-Object { [string]$_.BillingPlan } | Sort-Object -Unique)

    $scenario = if (-not $m -or -not $x) { 'Unknown' }
    elseif ($pcore) { 'PhysicalCoreLicense' }
    elseif ($licenseType -eq 'PAYG') { 'DirectPAYG' }
    else { 'NotPAYG' }

    $attention = [System.Collections.Generic.List[string]]::new()
    $info = [System.Collections.Generic.List[string]]::new()
    if (-not $m) { $attention.Add('NO_MACHINE') }
    elseif ($arcStatus -ne 'Connected') { $attention.Add('ARC_NOT_CONNECTED') }
    if ($m) {
      if (-not $x) { $attention.Add('EXT_MISSING') } elseif ($extState -ne 'Succeeded') { $attention.Add('EXT_NOT_SUCCEEDED') }
      if (([string]$m.SqlDiscovered) -ne 'true') { $info.Add('SQL_NOT_DISCOVERED') }
    }
    if ($esuVersion -and $x -and ([string]$x.EnableESU) -ne 'true') { $attention.Add('ESU_MISSING') }
    if ($scenario -eq 'PhysicalCoreLicense') {
      if ($cand.Count -eq 0) { $attention.Add('PCORE_NO_LICENSE_VISIBLE') }
      elseif ($plans -notcontains $licenseType) { $attention.Add('PCORE_PLAN_MISMATCH') }
    }
    if ($freeOnly) { $info.Add('FREE_EDITIONS_ONLY') }
    if ($scenario -eq 'DirectPAYG' -and ([string]$x.Consent) -ne 'true') { $info.Add('CONSENT_NOT_REPORTED') }

    [pscustomobject][ordered]@{
      Snapshot             = $SnapshotLabel
      CapturedAtUtc        = $CapturedAt
      HostId               = $hostId
      MachineName          = if ($m) { [string]$m.MachineName } else { '' }
      SubscriptionId       = $hostSub
      ResourceGroup        = if ($m) { [string]$m.ResourceGroup } else { ($hostId -split '/')[4] }
      Scenario             = $scenario
      Check                = if ($attention.Count -gt 0) { 'ATTENTION' } else { 'OK' }
      Findings             = (@($attention) + @($info)) -join ';'
      LicenseType          = $licenseType
      UsePhysicalCoreLicense = if ($pcore) { 'true' } else { 'false' }
      PhysicalCoreLicensePlans = $plans -join ';'
      EnableESU            = if ($x) { [string]$x.EnableESU } else { '' }
      ArcStatus            = $arcStatus
      ExtensionState       = $extState
      ExtensionVersion     = if ($x) { [string]$x.ExtensionVersion } else { '' }
      Instances            = $g.Count
      TopEdition           = $topEdition
      Editions             = $editions -join ';'
      Versions             = $versions -join ';'
      CoreEstimateNotBilling = $cores
      LastInstanceInventory = $lastInv
    }
  }
}

function Invoke-SnapshotMain {
  if (-not (Get-Command Invoke-AzRestMethod -ErrorAction SilentlyContinue)) { throw 'Az.Accounts is required (Connect-AzAccount).' }
  if (-not (Get-AzContext)) { throw 'Not signed in. Run Connect-AzAccount first.' }
  $subs = @($Subscriptions)
  if (-not $subs) { $subs = @(Get-AzSubscription -WarningAction SilentlyContinue | Where-Object State -eq 'Enabled' | ForEach-Object Id) }
  if (-not $subs) { throw 'No subscriptions found.' }
  Write-Host "Subscriptions in scope: $($subs.Count)"

  $data = @{}
  foreach ($k in $script:Queries.Keys) {
    $data[$k] = Invoke-ArgPaged -Query $script:Queries[$k] -Subs $subs
    Write-Host ("  {0,-11} {1} rows" -f $k, $data[$k].Count)
  }

  $stamp = (Get-Date).ToUniversalTime()
  $records = @(New-HostRecords -Instances $data.Instances -Machines $data.Machines -Extensions $data.Extensions -Licenses $data.Licenses -SnapshotLabel $Label -CapturedAt $stamp.ToString('s'))
  $null = New-Item -ItemType Directory -Force -Path $OutDir
  $safe = ($Label -replace '[^A-Za-z0-9._-]', '_')
  $file = Join-Path $OutDir ("snapshot_{0}_{1}.csv" -f $safe, $stamp.ToString('yyyyMMdd_HHmmss'))
  $records | Export-Csv -Path $file -NoTypeInformation -Encoding utf8NoBOM

  Write-Host "Snapshot: $file"
  Write-Host "Hosts with SQL instances: $($records.Count)"
  $records | Group-Object Scenario | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-20} {1}" -f $_.Name, $_.Count) }
  Write-Host "Check ATTENTION: $(@($records | Where-Object Check -eq 'ATTENTION').Count)  (cores are estimates, not billing)"
  $file
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-SnapshotMain }
