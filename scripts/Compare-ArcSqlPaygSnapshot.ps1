#Requires -Version 7.0
<#
.SYNOPSIS
  Compares two snapshots made by Export-ArcSqlPaygSnapshot.ps1 (BEFORE and AFTER a PAYG change). Offline; reads two CSV files only.
  Compara dois snapshots do Export-ArcSqlPaygSnapshot.ps1 (ANTES e DEPOIS de uma mudanca PAYG). Offline; le apenas dois CSV.

.DESCRIPTION
  Works for any path to PAYG: direct PAYG or physical core license (unlimited virtualization).
  Output:
    - console summary: scenario transitions, hosts added or removed, hosts that changed, hosts still not PAYG, hosts with ATTENTION after
    - a CSV with one row per changed field (Change, HostId, MachineName, Field, Before, After)
  -PlannedHostsCsv (optional): a CSV with a column MachineName or HostId listing the hosts you meant to convert.
    Each planned host gets a verdict: CONVERTED (After scenario is DirectPAYG or PhysicalCoreLicense with Check OK),
    CONVERTED_WITH_ATTENTION, NOT_CONVERTED, or NOT_FOUND_AFTER.
  Timing note: the ARG state can lag behind the change; run the AFTER snapshot after the change has propagated
  (how long it takes is not verified).
  Cores are estimates, not billing. This script does not prove billing, entitlement or compliance.

.EXAMPLE
  ./Compare-ArcSqlPaygSnapshot.ps1 -Before .\arc-payg-snapshots\snapshot_Before_*.csv -After .\arc-payg-snapshots\snapshot_After_*.csv
  ./Compare-ArcSqlPaygSnapshot.ps1 -Before b.csv -After a.csv -PlannedHostsCsv planned.csv -OutDir .\out
#>
[CmdletBinding()]
param(
  [string]$Before,
  [string]$After,
  [string]$PlannedHostsCsv,
  [string]$OutDir = (Join-Path (Get-Location) 'arc-payg-snapshots')
)

$ErrorActionPreference = 'Stop'

$script:CompareFields = 'MachineName', 'Scenario', 'Check', 'Findings', 'LicenseType', 'UsePhysicalCoreLicense', 'PhysicalCoreLicensePlans', 'EnableESU', 'ArcStatus', 'ExtensionState', 'ExtensionVersion', 'Instances', 'TopEdition', 'Versions', 'CoreEstimateNotBilling'
$script:PaygScenarios = 'DirectPAYG', 'PhysicalCoreLicense'

function Compare-Snapshots {
  param($BeforeRows, $AfterRows)
  $b = @{}; foreach ($r in $BeforeRows) { $b[[string]$r.HostId] = $r }
  $a = @{}; foreach ($r in $AfterRows) { $a[[string]$r.HostId] = $r }
  foreach ($id in ($b.Keys + $a.Keys | Sort-Object -Unique)) {
    if (-not $a.ContainsKey($id)) {
      [pscustomobject]@{ Change = 'Removed'; HostId = $id; MachineName = [string]$b[$id].MachineName; Field = ''; Before = ''; After = '' }
    } elseif (-not $b.ContainsKey($id)) {
      [pscustomobject]@{ Change = 'Added'; HostId = $id; MachineName = [string]$a[$id].MachineName; Field = ''; Before = ''; After = '' }
    } else {
      foreach ($f in $script:CompareFields) {
        $x = [string]$b[$id].$f; $y = [string]$a[$id].$f
        if ($x -ne $y) {
          [pscustomobject]@{ Change = 'Changed'; HostId = $id; MachineName = [string]$a[$id].MachineName; Field = $f; Before = $x; After = $y }
        }
      }
    }
  }
}

function Get-PlannedVerdicts {
  param($Planned, $BeforeRows, $AfterRows)
  $byId = @{}; $byName = @{}
  foreach ($r in $AfterRows) {
    $byId[[string]$r.HostId] = $r
    if ([string]$r.MachineName) { $byName[([string]$r.MachineName).ToLowerInvariant()] = $r }
  }
  foreach ($p in $Planned) {
    $key = if ($p.PSObject.Properties['HostId'] -and [string]$p.HostId) { [string]$p.HostId } else { [string]$p.MachineName }
    $row = if ($p.PSObject.Properties['HostId'] -and [string]$p.HostId) { $byId[$key.ToLowerInvariant()] } else { $byName[$key.ToLowerInvariant()] }
    $verdict = if (-not $row) { 'NOT_FOUND_AFTER' }
    elseif ($row.Scenario -in $script:PaygScenarios -and $row.Check -eq 'OK') { 'CONVERTED' }
    elseif ($row.Scenario -in $script:PaygScenarios) { 'CONVERTED_WITH_ATTENTION' }
    else { 'NOT_CONVERTED' }
    [pscustomobject]@{ Planned = $key; Verdict = $verdict; ScenarioAfter = [string]$row.Scenario; LicenseTypeAfter = [string]$row.LicenseType; CheckAfter = [string]$row.Check; FindingsAfter = [string]$row.Findings }
  }
}

function Invoke-CompareMain {
  if (-not $Before -or -not $After) { throw 'Provide -Before and -After (CSV files from Export-ArcSqlPaygSnapshot.ps1).' }
  $bf = @(Resolve-Path $Before -ErrorAction Stop | Select-Object -Last 1)[0].Path
  $af = @(Resolve-Path $After -ErrorAction Stop | Select-Object -Last 1)[0].Path
  $beforeRows = @(Import-Csv -Path $bf -Encoding utf8)
  $afterRows = @(Import-Csv -Path $af -Encoding utf8)
  foreach ($set in @(@('Before', $beforeRows), @('After', $afterRows))) {
    if ($set[1].Count -eq 0 -or -not $set[1][0].PSObject.Properties['HostId'] -or -not $set[1][0].PSObject.Properties['Scenario']) { throw "$($set[0]) file is empty or is not a snapshot (needs HostId and Scenario)." }
  }

  $changes = @(Compare-Snapshots -BeforeRows $beforeRows -AfterRows $afterRows)
  Write-Host "Before: $bf  ($($beforeRows.Count) hosts, $(($beforeRows[0]).CapturedAtUtc) UTC)"
  Write-Host "After:  $af  ($($afterRows.Count) hosts, $(($afterRows[0]).CapturedAtUtc) UTC)"

  Write-Host "`nScenario transitions (hosts present in both):"
  $bById = @{}; foreach ($r in $beforeRows) { $bById[[string]$r.HostId] = $r }
  $trans = foreach ($r in $afterRows) { $o = $bById[[string]$r.HostId]; if ($o) { "$($o.Scenario) -> $($r.Scenario)" } }
  $trans | Group-Object | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-45} {1}" -f $_.Name, $_.Count) }

  $added = @($changes | Where-Object Change -eq 'Added').Count
  $removed = @($changes | Where-Object Change -eq 'Removed').Count
  $changedHosts = @($changes | Where-Object Change -eq 'Changed' | Select-Object -ExpandProperty HostId -Unique).Count
  Write-Host "`nHosts added: $added   removed: $removed   with changed fields: $changedHosts"

  $stillNot = @($afterRows | Where-Object Scenario -eq 'NotPAYG')
  $attention = @($afterRows | Where-Object Check -eq 'ATTENTION')
  Write-Host "After: NotPAYG hosts: $($stillNot.Count)   ATTENTION hosts: $($attention.Count)"
  $attention | Group-Object { $_.Findings -split ';' | Where-Object { $_ -in 'NO_MACHINE', 'ARC_NOT_CONNECTED', 'EXT_MISSING', 'EXT_NOT_SUCCEEDED', 'ESU_MISSING', 'PCORE_NO_LICENSE_VISIBLE', 'PCORE_PLAN_MISMATCH' } | Select-Object -First 1 } |
    Sort-Object Count -Descending | ForEach-Object { Write-Host ("  first finding {0,-26} {1}" -f $_.Name, $_.Count) }

  $null = New-Item -ItemType Directory -Force -Path $OutDir
  $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
  $out = Join-Path $OutDir "compare_$stamp.csv"
  $changes | Export-Csv -Path $out -NoTypeInformation -Encoding utf8NoBOM
  Write-Host "`nChanges CSV: $out"

  if ($PlannedHostsCsv) {
    $planned = @(Import-Csv -Path $PlannedHostsCsv -Encoding utf8)
    $verdicts = @(Get-PlannedVerdicts -Planned $planned -BeforeRows $beforeRows -AfterRows $afterRows)
    $vout = Join-Path $OutDir "planned_$stamp.csv"
    $verdicts | Export-Csv -Path $vout -NoTypeInformation -Encoding utf8NoBOM
    Write-Host "`nPlanned hosts ($($verdicts.Count)):"
    $verdicts | Group-Object Verdict | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-26} {1}" -f $_.Name, $_.Count) }
    Write-Host "Planned verdicts CSV: $vout"
  }
  Write-Host "`nCores are estimates, not billing. Confirm charges in Cost Management."
  $out
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-CompareMain }
