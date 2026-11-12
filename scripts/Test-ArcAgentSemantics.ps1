#Requires -Version 7.0
<#
.SYNOPSIS
  Executes anonymous agent-workbook regression fixtures in Azure Resource Graph (read-only).
  Executa casos anonimos de regressao do workbook no Azure Resource Graph (somente leitura).
.DESCRIPTION
  Uses an existing Az.Accounts context; never starts interactive authentication.
  Usa contexto Az.Accounts existente; nunca inicia autenticacao interativa.
  Requires at least one resource in the selected subscription to seed fixtures.
  Requer pelo menos um recurso na assinatura selecionada para iniciar os casos.
#>
[CmdletBinding()]
param(
  [string]$WorkbookPath = (Join-Path $PSScriptRoot '..\workbooks\arc-agent-support-workbook.json'),
  [string]$Subscription
)
$ErrorActionPreference = 'Stop'
Import-Module Az.Accounts -ErrorAction Stop
if (-not $Subscription) { $Subscription = (Get-AzContext -ErrorAction Stop).Subscription.Id }
if (-not $Subscription) { throw 'An existing Azure context or -Subscription is required; no login is attempted.' }
$workbook = Get-Content -LiteralPath $WorkbookPath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
function Get-Items($Items) {
  foreach ($item in $Items) {
    $item
    if ($item.type -eq 12) { Get-Items $item.content.items }
  }
}
$items = @(Get-Items $workbook.items)
$script:caseCount = 0
function Get-Query([string]$Name) { ($items | Where-Object name -eq $Name).content.query }
function Get-Line([string]$Query, [string]$Prefix) {
  $lines = @($Query -split '\r?\n' | Where-Object { $_.StartsWith($Prefix) })
  if ($lines.Count -ne 1) { throw "Expected one query line: $Prefix; found $($lines.Count)" }
  $lines[0]
}
function Invoke-Fixture([string]$Name, [string]$Query, [int]$ExpectedCount) {
  $payload = @{ query = $Query; subscriptions = @($Subscription); options = @{ resultFormat = 'objectArray' } } | ConvertTo-Json -Depth 30
  for ($attempt = 0; $attempt -lt 6; $attempt++) {
    $response = Invoke-AzRestMethod -Method POST -Path '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Payload $payload -ErrorAction Stop
    if ($response.StatusCode -ne 429) { break }
    Start-Sleep -Seconds (5 * ($attempt + 1))
  }
  if ($response.StatusCode -ne 200) { throw "$Name HTTP $($response.StatusCode): $($response.Content)" }
  $body = $response.Content | ConvertFrom-Json -Depth 100
  if ($body.resultTruncated -eq $true -or $body.resultTruncated -eq 'true' -or $body.'$skipToken') { throw "$Name returned incomplete results." }
  $rows = @($body.data)
  $failed = @($rows | Where-Object { $_.Passed -ne $true })
  if ($rows.Count -ne $ExpectedCount -or $failed.Count) {
    throw "$Name failed: expected $ExpectedCount rows, got $($rows.Count); $($failed | ConvertTo-Json -Depth 20 -Compress)"
  }
  Write-Host "PASS $Name ($ExpectedCount cases)"
  $script:caseCount += $ExpectedCount
}
function Get-Source($Cases) {
  $json = ConvertTo-Json -InputObject @($Cases) -Depth 30 -Compress
  "resources | take 1 | project fixtures = dynamic($json) | mv-expand c = fixtures"
}

$base = Get-Query 'inventory'
$cases = @(
  @{ agent = 1069; reference = 1069; expected = 'At reference' },
  @{ agent = 1070; reference = 1069; expected = 'Ahead of reference' },
  @{ agent = 1059; reference = 1070; expected = 'Within configured window' },
  @{ agent = 1058; reference = 1070; expected = 'Outside configured window' },
  @{ agent = $null; reference = 1070; expected = 'Unknown' },
  @{ agent = 1069; reference = $null; expected = 'Unknown' }
)
$query = @(
  Get-Source $cases
  '| project agentRank = toint(c.agent), latestRank = toint(c.reference), Expected = tostring(c.expected)'
  Get-Line $base '| extend versionsBehind ='
  Get-Line $base '| extend versionComparison ='
  '| project Expected, Actual = versionComparison, Passed = Expected == versionComparison'
) -join "`n"
Invoke-Fixture 'version-comparison-boundaries' ($query.Replace('{SupportWindow}', '12')) $cases.Count

$cases = @(
  @{ agent = 1060; expected = 'Below security floor' },
  @{ agent = 1061; expected = 'At or above configured floor' },
  @{ agent = 1062; expected = 'At or above configured floor' },
  @{ agent = $null; expected = 'Unknown' }
)
$query = @(
  Get-Source $cases
  '| project agentRank = toint(c.agent), Expected = tostring(c.expected)'
  Get-Line $base '| extend floorRank ='
  Get-Line $base '| extend securityFloor ='
  '| project Expected, Actual = securityFloor, Passed = Expected == securityFloor'
) -join "`n"
Invoke-Fixture 'configured-floor-boundaries' ($query.Replace('{SecurityFloorVersion}', '1.61')) $cases.Count

$cases = @(
  @{ Override = 1066; Auto = 1070; Expected = 1066 },
  @{ Override = 1071; Auto = 1070; Expected = 1071 },
  @{ Override = $null; Auto = 1070; Expected = 1070 },
  @{ Override = $null; Auto = -1; Expected = $null }
)
$query = @(
  Get-Source $cases
  '| project overrideRank = toint(c.Override), autoLatest = toint(c.Auto), Expected = toint(c.Expected)'
  Get-Line $base '| extend latestRank ='
  '| project Expected, Actual = latestRank, Passed = (isnull(Expected) and isnull(latestRank)) or Expected == latestRank'
) -join "`n"
Invoke-Fixture 'manual-reference-priority' $query $cases.Count

$cases = @(
  @{ agent = 1066; reference = 1070; enabled = 'Enabled'; status = 'Connected'; attempt = ''; expected = 'Below minimum (manual upgrade)' },
  @{ agent = 1067; reference = 1068; enabled = 'Enabled'; status = 'Connected'; attempt = ''; expected = 'On track' },
  @{ agent = 1069; reference = 1070; enabled = 'N/A'; status = 'Connected'; attempt = ''; expected = 'Unknown enablement' },
  @{ agent = 1069; reference = 1070; enabled = 'Disabled'; status = 'Connected'; attempt = ''; expected = 'Disabled (minimum met)' },
  @{ agent = 1069; reference = 1070; enabled = 'Enabled'; status = 'Disconnected'; attempt = ''; expected = 'Blocked (not connected)' },
  @{ agent = 1069; reference = 1070; enabled = 'Enabled'; status = 'Connected'; attempt = 'Failed'; expected = 'Failing' },
  @{ agent = 1068; reference = 1070; enabled = 'Enabled'; status = 'Connected'; attempt = ''; expected = 'Lagging' },
  @{ agent = 1069; reference = $null; enabled = 'Enabled'; status = 'Connected'; attempt = ''; expected = 'Unknown reference' },
  @{ agent = $null; reference = 1070; enabled = 'Disabled'; status = 'Connected'; attempt = ''; expected = 'Unknown' }
)
$query = @(
  Get-Source $cases
  '| project agentRank = toint(c.agent), latestRank = toint(c.reference), autoUpgradeLabel = tostring(c.enabled), status = tostring(c.status), lastAttemptStatus = tostring(c.attempt), Expected = tostring(c.expected)'
  '| extend minAutoRank = 1067'
  Get-Line $base '| extend versionsBehind ='
  Get-Line $base '| extend upgradeHealth ='
  '| project Expected, Actual = upgradeHealth, Passed = Expected == upgradeHealth'
) -join "`n"
Invoke-Fixture 'automatic-upgrade-evidence' ($query.Replace('{AutoUpgradeTolerance}', '1')) $cases.Count

$cases = @(
  @{ agent = 1069; reference = 1069; enabled = 'Enabled'; status = 'Connected'; attempt = '' },
  @{ agent = 1070; reference = 1069; enabled = 'Disabled'; status = 'Connected'; attempt = '' },
  @{ agent = 1057; reference = 1070; enabled = 'Enabled'; status = 'Expired'; attempt = 'Failed' }
)
foreach ($test in @(@{ Name = 'kpi-row0-tiles'; Count = 5 }, @{ Name = 'kpi-row1-tiles'; Count = 6 })) {
  $kpi = Get-Query $test.Name
  $query = @(
    Get-Source $cases
    '| project agentRank = toint(c.agent), latestRank = toint(c.reference), autoUpgradeLabel = tostring(c.enabled), status = tostring(c.status), lastAttemptStatus = tostring(c.attempt)'
    '| extend minAutoRank = 1067, floorRank = 1061'
    Get-Line $base '| extend versionsBehind ='
    Get-Line $base '| extend versionComparison ='
    Get-Line $base '| extend upgradeHealth ='
    Get-Line $base '| extend securityFloor ='
    $kpi.Substring($kpi.IndexOf('| summarize Total ='))
    '| extend Expected = case(Order == 1, 3, Order in (2,6,7), 2, Order in (3,5,9), 0, 1)'
    '| project Order, Expected, Actual = Value, Passed = Expected == Value'
  ) -join "`n"
  $query = $query.Replace('{SupportWindow}', '12').Replace('{AutoUpgradeTolerance}', '1').Replace('{Language}', 'EN')
  Invoke-Fixture "$($test.Name)-version-and-upgrade-counts" $query $test.Count
}
foreach ($test in @(
  @{ Language = 'EN'; Expected = '7 days in the current state' },
  @{ Language = 'PT'; Expected = '7 dias no estado atual' }
)) {
  $banner = Get-Query 'kpi-banner'
  $query = @(
    'resources | take 1 | project Total = 2, Offline = 1, MaxDays = 7'
    $banner.Substring($banner.IndexOf('| extend Msg ='))
    "| project Passed = Msg contains '$($test.Expected)'"
  ) -join "`n"
  Invoke-Fixture "banner-time-in-state-$($test.Language)" ($query.Replace('{Language}', $test.Language)) 1
}

$cases = @(
  @{ state = 'Succeeded'; message = '{"SystemErrors":[],"InstancesStatus":[{"Status":"Not Protected","Errors":["Worker failed"]}]}'; expected = 'Health warning' },
  @{ state = 'Succeeded'; message = 'prefix {"SystemErrors":[],"InstancesStatus":[{"Status":"Not Protected","Errors":["Worker failed"]}]} trailing text'; expected = 'Health warning' },
  @{ state = 'Succeeded'; message = '{"SystemErrors":["Error"],"InstancesStatus":[]}'; expected = 'Health warning' },
  @{ state = 'Succeeded'; message = '{"healthIssues":["Unhealthy"]}'; expected = 'Health warning' },
  @{ state = 'Failed'; message = 'Unable to run'; expected = 'Failure' },
  @{ state = 'Succeeded'; message = 'Non-JSON diagnostic'; expected = 'Diagnostic review' },
  @{ state = 'Succeeded'; message = '{"SystemErrors":['; expected = 'Diagnostic review' },
  @{ state = 'Succeeded'; message = '{"UnknownSchema":true}'; expected = 'Diagnostic review' },
  @{ state = 'Succeeded'; message = '{"SystemErrors":[],"InstancesStatus":[{"Status":"Protected","Errors":[]}]}'; expected = 'Not assessed' },
  @{ state = 'Succeeded'; message = ''; expected = 'Not assessed' }
)
foreach ($name in 'ext-detail','ext-issues') {
  $extension = Get-Query $name
  $start = $extension.IndexOf('| extend _jsonText =')
  $end = $extension.IndexOf('| extend Issue = replace_regex', $start)
  if ($start -lt 0 -or $end -lt 0) { throw "Diagnostic block not found: $name" }
  $query = @(
    Get-Source $cases
    '| project _state = tostring(c.state), _msg = tostring(c.message), Expected = tostring(c.expected)'
    $extension.Substring($start, $end - $start)
    '| project Expected, Actual = IssueCategory, Passed = Expected == IssueCategory'
  ) -join "`n"
  Invoke-Fixture "$name-functional-diagnostics" $query $cases.Count
}

$cases = @(
  @{ ver = ''; expected = 'Unknown (installed version missing or invalid)' },
  @{ ver = 'invalid'; expected = 'Unknown (installed version missing or invalid)' },
  @{ ver = '1.0'; expected = 'Not returned by selected regional catalog' },
  @{ ver = '2.0'; expected = 'At regional catalog reference' },
  @{ ver = '3.0'; expected = 'Ahead of regional catalog' }
)
$detail = Get-Query 'ext-detail'
$rank = (Get-Line $detail '| extend vr =').Split(', avail = ')[0]
$query = @(
  Get-Source $cases
  '| project ver = tostring(c.ver), Expected = tostring(c.expected)'
  $rank
  '| extend availCount = 1, availMax = long(2000000000000000), tr = long(2000000000000000), listed = 0'
  Get-Line $detail '| extend VersionStatus ='
  '| project Expected, Actual = VersionStatus, Passed = Expected == VersionStatus'
) -join "`n"
Invoke-Fixture 'extension-catalog-uncertainty' $query $cases.Count

$cases = @(@{ ver = '4.11' }, @{ ver = '1.5.87' })
$extension = Get-Query 'extensions'
$query = @(
  Get-Source $cases
  '| project machineId = tostring(c.ver), ver = tostring(c.ver), Publisher = "test", ExtensionType = "test", location = "test", State = "Succeeded", au = false'
  $extension.Substring($extension.IndexOf('| extend vr ='))
  "| project Passed = NewestInstalled == '4.11' and OldestInstalled == '1.5.87'"
) -join "`n"
Invoke-Fixture 'reported-extension-version-format' $query 1

$paths = Get-Query 'upgrade-paths'
$cases = @(
  @{ comparison = 'Ahead of reference'; below = 0; offline = 0; failed = 0; unknown = 0; expected = 'Ahead of reference; do not downgrade' },
  @{ comparison = 'Within configured window'; below = 1; offline = 0; failed = 0; unknown = 0; expected = 'Manual upgrade needed for minimum; verify OS-compatible version' },
  @{ comparison = 'Within configured window'; below = 0; offline = 1; failed = 0; unknown = 0; expected = 'Restore connectivity; review local upgrade separately' },
  @{ comparison = 'Within configured window'; below = 0; offline = 0; failed = 1; unknown = 0; expected = 'Investigate failed automatic upgrade' },
  @{ comparison = 'Within configured window'; below = 0; offline = 0; failed = 0; unknown = 1; expected = 'Verify automatic upgrade setting and prerequisites' },
  @{ comparison = 'Within configured window'; below = 0; offline = 0; failed = 0; unknown = 0; expected = 'Auto-upgrade enabled; verify prerequisites and monitor rollout' }
)
$query = @(
  Get-Source $cases
  '| project VersionComparison = tostring(c.comparison), BelowMinimum = toint(c.below), Offline = toint(c.offline), FailedAttempts = toint(c.failed), UnknownEnablement = toint(c.unknown), Expected = tostring(c.expected), Machines = 1, AutoUpgradeOn = 1, bf = 0'
  Get-Line $paths '| extend Action ='
  '| project Expected, Actual = Action, Passed = Expected == Action'
) -join "`n"
Invoke-Fixture 'upgrade-path-blockers' $query $cases.Count

$available = Get-Query 'ext-available'
$available = $available.Replace("resources`n| where type =~ 'microsoft.hybridcompute/machines/extensions'", @"
resources | take 1
| project id = 'fixture/machine/extensions/test', location = 'test', properties = dynamic({"publisher":"test","type":"test","typeHandlerVersion":"1.2.3"})
"@)
$available = $available.Replace("    resources`n    | where type =~ 'microsoft.hybridcompute/machines'", @"
    resources | take 1
    | project id = 'fixture/machine', properties = dynamic({"osType":"windows","status":"Connected","agentUpgrade":{"enableAutomaticUpgrade":true}})
"@)
foreach ($test in @(
  @{ Name = 'matching-machine'; OS = 'windows'; State = 'Connected'; Auto = 'Enabled'; Expected = 1 },
  @{ Name = 'excluded-connection'; OS = 'All'; State = 'Expired'; Auto = 'All'; Expected = 0 },
  @{ Name = 'excluded-os'; OS = 'linux'; State = 'All'; Auto = 'All'; Expected = 0 },
  @{ Name = 'excluded-auto-upgrade'; OS = 'All'; State = 'All'; Auto = 'Disabled'; Expected = 0 },
  @{ Name = 'all-machines'; OS = 'All'; State = 'All'; Auto = 'All'; Expected = 1 }
)) {
  $query = $available.Replace('{ExtPublisher}', 'test').Replace('{ExtType}', 'test').Replace('{ExtLocation}', 'test').
    Replace('{ExtAvailable}', '1.2.3').Replace('{ExtAvailableJson}', '1.2.3').
    Replace('{OsFilter}', "'$($test.OS)'").Replace('{StatusFilter}', "'$($test.State)'").Replace('{AutoUpgradeFilter}', "'$($test.Auto)'")
  $query += "`n| summarize Total = sum(Machines) | project Passed = Total == $($test.Expected)"
  Invoke-Fixture "extension-count-$($test.Name)" $query 1
}
Write-Host "All $script:caseCount anonymous semantic cases passed. This does not validate portal rendering or official support."
