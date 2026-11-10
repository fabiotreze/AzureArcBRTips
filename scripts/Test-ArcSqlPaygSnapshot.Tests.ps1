#Requires -Version 7.0
<#
.SYNOPSIS
  Offline tests for Export-ArcSqlPaygSnapshot.ps1 and Compare-ArcSqlPaygSnapshot.ps1 (no Azure connection, no Pester).
  Testes offline do Export e do Compare (sem conexao ao Azure, sem Pester). Comparacoes usam ASCII.
.EXAMPLE
  pwsh -NoProfile -File .\scripts\Test-ArcSqlPaygSnapshot.Tests.ps1
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Export-ArcSqlPaygSnapshot.ps1')
. (Join-Path $PSScriptRoot 'Compare-ArcSqlPaygSnapshot.ps1')

$script:fail = 0; $script:pass = 0
function Assert-Equal {
  param($Actual, $Expected, [string]$Name)
  if ([string]$Actual -ceq [string]$Expected) { $script:pass++; Write-Host "PASS $Name" }
  else { $script:fail++; Write-Host "FAIL $Name : expected '$Expected' got '$Actual'" }
}

$sub = '00000000-0000-0000-0000-000000000001'
function Hid([string]$n) { "/subscriptions/$sub/resourcegroups/rg/providers/microsoft.hybridcompute/machines/$n" }
function Inst($n, $ed, $ver, $lic = '') { [pscustomobject]@{ HostId = (Hid $n); Edition = $ed; Version = $ver; InstanceLicenseType = $lic; LastInstanceInventory = '2026-11-01T00:00:00Z' } }
function Mach($n, $status = 'Connected', $cores = 8) { [pscustomobject]@{ HostId = (Hid $n); MachineName = $n; SubscriptionId = $sub; ResourceGroup = 'rg'; ArcStatus = $status; OsType = 'windows'; SqlDiscovered = 'true'; LogicalCores = $cores; PhysicalCores = $null; Manufacturer = 'VMware, Inc.'; Model = 'VMware Virtual Platform' } }
function Ext($n, $lic, $pcore = 'false', $esu = '', $state = 'Succeeded') { [pscustomobject]@{ HostId = (Hid $n); ExtensionState = $state; ExtensionVersion = '1.1'; LicenseType = $lic; UsePcore = $pcore; EnableESU = $esu; Consent = '' } }

$instances = @(
  (Inst 'direct' 'Enterprise Edition' 'SQL Server 2019'),
  (Inst 'pcoreok' 'Enterprise Edition' 'SQL Server 2022'),
  (Inst 'pcoremismatch' 'Enterprise Edition' 'SQL Server 2022'),
  (Inst 'paid2016' 'Enterprise Edition' 'SQL Server 2016'),
  (Inst 'nomachine' 'Standard Edition' 'SQL Server 2019'),
  (Inst 'free' 'Express Edition' 'SQL Server 2022'),
  (Inst 'std' 'Standard Edition' 'SQL Server 2019'),
  (Inst 'direct' 'Enterprise Edition' 'SQL Server 2019' 'HADR')
)
$machines = @((Mach 'direct'), (Mach 'pcoreok'), (Mach 'pcoremismatch'), (Mach 'paid2016' 'Disconnected'), (Mach 'free'), (Mach 'std' 'Connected' 64))
$exts = @((Ext 'direct' 'PAYG'), (Ext 'pcoreok' 'PAYG' 'true'), (Ext 'pcoremismatch' 'PAYG' 'true'), (Ext 'paid2016' 'Paid'), (Ext 'free' 'Paid'), (Ext 'std' 'Paid'))
$lic = @([pscustomobject]@{ LicenseSubscriptionId = $sub; BillingPlan = 'PAYG'; ActivationState = 'Activated'; ScopeType = 'Subscription'; LicenseCores = 64 })

$rows = @(New-HostRecords -Instances $instances -Machines $machines -Extensions $exts -Licenses $lic -SnapshotLabel 'T' -CapturedAt '2026-11-10T00:00:00')
function Row($n) { $rows | Where-Object { $_.HostId -eq (Hid $n) } }

Assert-Equal $rows.Count 7 'one row per host'
Assert-Equal (Row 'direct').Scenario 'DirectPAYG' 'direct PAYG scenario'
Assert-Equal (Row 'direct').Check 'OK' 'direct PAYG check ok'
Assert-Equal (Row 'direct').Instances 2 'instances grouped by host'
Assert-Equal (Row 'direct').CoreEstimateNotBilling 8 'direct cores'
Assert-Equal (Row 'pcoreok').Scenario 'PhysicalCoreLicense' 'pcore scenario'
Assert-Equal (Row 'pcoreok').Check 'OK' 'pcore with matching plan ok'
Assert-Equal (Row 'pcoremismatch').Check 'OK' 'pcore plan PAYG matches LicenseType PAYG'

$licPaid = @([pscustomobject]@{ LicenseSubscriptionId = $sub; BillingPlan = 'Paid'; ActivationState = 'Activated'; ScopeType = 'Subscription'; LicenseCores = 64 })
$rows2 = @(New-HostRecords -Instances $instances -Machines $machines -Extensions $exts -Licenses $licPaid -SnapshotLabel 'T' -CapturedAt 'x')
Assert-Equal (($rows2 | Where-Object { $_.HostId -eq (Hid 'pcoremismatch') }).Findings -like '*PCORE_PLAN_MISMATCH*') 'True' 'pcore plan mismatch when license is Paid'
$rows3 = @(New-HostRecords -Instances $instances -Machines $machines -Extensions $exts -Licenses @() -SnapshotLabel 'T' -CapturedAt 'x')
Assert-Equal (($rows3 | Where-Object { $_.HostId -eq (Hid 'pcoreok') }).Findings -like '*PCORE_NO_LICENSE_VISIBLE*') 'True' 'pcore without visible license'

Assert-Equal (Row 'paid2016').Scenario 'NotPAYG' 'paid is NotPAYG'
Assert-Equal ((Row 'paid2016').Findings -like '*ESU_MISSING*') 'True' 'ESU missing for 2016'
Assert-Equal ((Row 'paid2016').Findings -like '*ARC_NOT_CONNECTED*') 'True' 'disconnected flagged'
Assert-Equal (Row 'nomachine').Scenario 'Unknown' 'no machine is Unknown'
Assert-Equal ((Row 'nomachine').Findings -like 'NO_MACHINE*') 'True' 'no machine flagged'
Assert-Equal (Row 'free').CoreEstimateNotBilling 0 'free edition cores 0'
Assert-Equal ((Row 'free').Findings -like '*FREE_EDITIONS_ONLY*') 'True' 'free editions info'
Assert-Equal (Row 'std').CoreEstimateNotBilling 24 'standard cores capped at 24'

# Compare: host moves from NotPAYG to DirectPAYG; one planned host stays.
$snapBefore = @(New-HostRecords -Instances $instances -Machines $machines -Extensions @((Ext 'direct' 'Paid'), (Ext 'paid2016' 'Paid'), (Ext 'std' 'Paid'), (Ext 'free' 'Paid'), (Ext 'pcoreok' 'Paid'), (Ext 'pcoremismatch' 'Paid')) -Licenses $lic -SnapshotLabel 'Before' -CapturedAt 'b')
$ch = @(Compare-Snapshots -BeforeRows $snapBefore -AfterRows $rows)
Assert-Equal (@($ch | Where-Object { $_.Field -eq 'Scenario' -and $_.MachineName -eq 'direct' })[0].After) 'DirectPAYG' 'compare sees scenario change'
Assert-Equal (@($ch | Where-Object { $_.Field -eq 'LicenseType' -and $_.MachineName -eq 'direct' })[0].Before) 'Paid' 'compare sees license type before'
Assert-Equal @($ch | Where-Object { $_.MachineName -eq 'std' }).Count 0 'unchanged host has no changes'
$rowsMinus = @($rows | Where-Object { $_.MachineName -ne 'std' })
Assert-Equal (@(Compare-Snapshots -BeforeRows $snapBefore -AfterRows $rowsMinus | Where-Object Change -eq 'Removed').Count) 1 'removed host detected'

$planned = @([pscustomobject]@{ MachineName = 'direct' }, [pscustomobject]@{ MachineName = 'std' }, [pscustomobject]@{ MachineName = 'paid2016' }, [pscustomobject]@{ MachineName = 'ghost' })
$v = @(Get-PlannedVerdicts -Planned $planned -BeforeRows $snapBefore -AfterRows $rows)
Assert-Equal ($v | Where-Object Planned -eq 'direct').Verdict 'CONVERTED' 'planned converted'
Assert-Equal ($v | Where-Object Planned -eq 'std').Verdict 'NOT_CONVERTED' 'planned not converted'
Assert-Equal ($v | Where-Object Planned -eq 'ghost').Verdict 'NOT_FOUND_AFTER' 'planned not found'

# CSV round trip keeps UTF-8 and values.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("arcpayg_" + [guid]::NewGuid().ToString('N') + '.csv')
try {
  $rows | Export-Csv -Path $tmp -NoTypeInformation -Encoding utf8NoBOM
  $back = @(Import-Csv -Path $tmp -Encoding utf8)
  Assert-Equal $back.Count 7 'csv round trip rows'
  Assert-Equal (@([IO.File]::ReadAllBytes($tmp) | Select-Object -First 3) -join ',') (@(0x22, 0x53, 0x6e) -join ',') 'csv has no BOM'
} finally { Remove-Item $tmp -ErrorAction SilentlyContinue }

Write-Host "$script:pass passed, $script:fail failed."
if ($script:fail -gt 0) { exit 1 }
