<#
.SYNOPSIS
  End-to-end test harness for Azure Workbooks (.workbook JSON) that use Azure Resource Graph (ARG) and ARM (queryType 12).

.DESCRIPTION
  Reads a workbook file, resolves its parameters exactly like the portal (static values, ARG-backed and ARM-backed
  parameters), then runs every query of every tab / section against YOUR tenant and writes a CSV + summary:
  status, row count, duration, 429 count, retries, truncation (1000 rows), error text.

  Modes
    -DryRun        No Azure call. Parses, resolves tokens, evaluates visibility, counts queries per tab (offline lint).
    (default)      Runs queries sequentially with 429-aware retry (functional test).
    -Burst         Runs all queries of a tab at the same time (like the portal does when a tab opens) to reproduce 429s.
    -FilterCombos  OneFactor | Full   Re-runs the tab queries for every combination of the multi-select filters
                   (OsFilter, StatusFilter, SupportFilter, AutoUpgradeFilter) to test parameter combinations.
    -ExtensionDrill N  Agent workbook only: simulates clicking the first N rows of the Extensions table.

  Requirements: PowerShell 7+, Az.Accounts, Az.ResourceGraph, Reader on the subscriptions. Read-only: nothing is modified.

.EXAMPLE
  Connect-AzAccount -Tenant <tenant-id>
  ./Test-ArcWorkbookQueries.ps1 -WorkbookPath ./arc-sql-payg-readiness-workbook.json -Language PT -Burst
  ./Test-ArcWorkbookQueries.ps1 -WorkbookPath ./arc-agent-support-workbook.json -Language EN -FilterCombos OneFactor -ExtensionDrill 3
  ./Test-ArcWorkbookQueries.ps1 -WorkbookPath ./arc-agent-support-workbook.json -DryRun
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$WorkbookPath,
  [string[]]$Subscriptions,
  [ValidateSet('EN','PT')][string]$Language = 'PT',
  [switch]$DryRun,
  [switch]$Burst,
  [ValidateSet('None','OneFactor','Full')][string]$FilterCombos = 'None',
  [int]$ExtensionDrill = 0,
  [hashtable]$SetParam = @{},
  [int]$MaxRetries = 5,
  [int]$ThrottleLimit = 40,
  [string]$OutDir = './workbook-test-results'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$wb = Get-Content -Raw -Path $WorkbookPath -Encoding utf8 | ConvertFrom-Json -Depth 100
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

# ---------- helpers ----------
function Get-Flat {
  param($Items, $Tab = 'Always')
  foreach ($it in $Items) {
    if ($it.type -eq 12) {
      $t = $Tab
      $cv = $it.conditionalVisibility
      if ($cv -and $cv.parameterName -eq 'SelectedTab') { $t = $cv.value }
      Get-Flat -Items $it.content.items -Tab $t
    } else {
      [pscustomobject]@{ Tab = $Tab; Item = $it }
    }
  }
}

function Test-Visible {
  param($Item, [hashtable]$P)
  $cv = $Item.conditionalVisibilities; if (-not $cv) { $cv = $Item.conditionalVisibility }
  if (-not $cv) { return $true }
  foreach ($v in @($cv)) {
    $cur = [string]$P[$v.parameterName]; $val = [string]$v.value
    switch ($v.comparison) {
      'isEqualTo'    { if ($cur -ne $val) { return $false } }
      'isNotEqualTo' { if ($cur -eq $val) { return $false } }
    }
  }
  return $true
}

function Expand-Tokens {
  param([string]$Text, [hashtable]$P)
  [regex]::Replace($Text, '\{([A-Za-z][A-Za-z0-9_]*)\}', { param($m)
    $n = $m.Groups[1].Value
    if ($P.ContainsKey($n)) { [string]$P[$n] } else { $m.Value }
  })
}

function Invoke-WithRetry {
  param([scriptblock]$Action)
  $n429 = 0; $attempt = 0
  while ($true) {
    try { return [pscustomobject]@{ Ok = $true; Value = (& $Action); N429 = $n429; Error = $null } }
    catch {
      $msg = $_.Exception.Message
      $throttled = $msg -match '429|TooManyRequests|throttl|RateLimit'
      if ($throttled) { $n429++ }
      $attempt++
      if ($throttled -and $attempt -le $MaxRetries) {
        $wait = 0
        if ($msg -match 'Retry-After\D+(\d+)') { $wait = [int]$Matches[1] }
        if ($wait -le 0) { $wait = [math]::Min(30, [math]::Pow(2, $attempt)) }
        Start-Sleep -Seconds $wait
        continue
      }
      return [pscustomobject]@{ Ok = $false; Value = $null; N429 = $n429; Error = $msg }
    }
  }
}

function Invoke-Arg {
  param([string]$Query, [string[]]$Subs)
  $all = @(); $skip = $null; $truncated = $false
  do {
    $args2 = @{ Query = $Query; First = 1000 }
    if ($Subs) { $args2.Subscription = $Subs }
    if ($skip) { $args2.SkipToken = $skip }
    $r = Search-AzGraph @args2 -ErrorAction Stop
    $all += @($r)
    $skip = $r.SkipToken
    if ($all.Count -ge 10000) { $truncated = $true; break }   # workbook grid limit
  } while ($skip)
  [pscustomobject]@{ Rows = $all; Truncated = $truncated }
}

function Invoke-ArmQuery {
  param([string]$Json)
  $q = $Json | ConvertFrom-Json -Depth 50
  $qs = ($q.urlParams | ForEach-Object { "$($_.key)=$($_.value)" }) -join '&'
  $path = $q.path + '?' + $qs
  $resp = Invoke-AzRestMethod -Method $q.method -Path $path -ErrorAction Stop
  if ($resp.StatusCode -ge 400) { throw "HTTP $($resp.StatusCode) $($resp.Content)" }
  $body = $resp.Content | ConvertFrom-Json -Depth 50
  $tr = $q.transformers | Select-Object -First 1
  $tp = $tr.settings.tablePath
  $rows = @()
  if ($tp -eq '$.value') { $rows = @($body.value) }
  elseif ($tp -match '^\$\.value\[\?\(@\.agentVersion >= ''(.*)''\)\]$') {
    $min = $Matches[1]; $rows = @($body.value | Where-Object { $_.agentVersion -ge $min })
  } elseif ($tp -eq '$') { $rows = @($body) }
  else { $rows = @($body.value) }
  $out = foreach ($r in $rows) {
    $o = [ordered]@{}
    foreach ($c in $tr.settings.columns) {
      $path = $c.path -replace '^\$\.', ''
      if ($path -like 'value[[]*].*') { $o[$c.columnid] = @($body.value | ForEach-Object { ($_ | Select-Object -ExpandProperty properties).version }) -join ','; continue }
      $cur = $r; foreach ($seg in $path.Split('.')) { if ($null -ne $cur) { $cur = $cur.$seg } }
      $o[$c.columnid] = $cur
    }
    [pscustomobject]$o
  }
  @($out)
}

function Format-ParamValue {
  param($Param, [string[]]$Values)
  $quote = if ($Param.quote) { [string]$Param.quote } else { '' }
  $delim = if ($Param.delimiter) { [string]$Param.delimiter } else { ',' }
  ($Values | ForEach-Object { "$quote$_$quote" }) -join $delim
}

function Resolve-Parameters {
  param([hashtable]$Override = @{}, [string[]]$Subs)
  $P = @{}
  $P['Language'] = $Language
  $options = @{}     # param name -> all option values (for filter combos)
  foreach ($pi in (Get-Flat -Items $wb.items | Where-Object { $_.Item.type -eq 9 })) {
    foreach ($prm in $pi.Item.content.parameters) {
      $name = $prm.name
      if ($Override.ContainsKey($name)) { $P[$name] = $Override[$name]; continue }
      if ($prm.type -eq 6) { $P[$name] = ($Subs -join ','); continue }
      if ($name -eq 'Language') { continue }
      if ($prm.query -and -not $DryRun) {
        if ($pi.Tab -ne 'Always') { continue }                      # lazy parameters resolve inside their tab
        $res = if ($prm.queryType -eq 12) { Invoke-WithRetry { Invoke-ArmQuery -Json (Expand-Tokens $prm.query $P) } }
               else { Invoke-WithRetry { (Invoke-Arg -Query (Expand-Tokens $prm.query $P) -Subs $Subs).Rows } }
        if (-not $res.Ok) { Write-Warning "Parameter $name failed: $($res.Error)"; $P[$name] = ''; continue }
        $rows = @($res.Value)
        $first = if ($rows.Count) { ($rows[0].PSObject.Properties | Select-Object -First 1).Name } else { $null }
        $vals = if ($first) { @($rows | ForEach-Object { [string]$_.$first }) } else { @() }
        Write-Host ('  parameter {0}: {1} value(s)' -f $name, $vals.Count)
        if ($prm.type -eq 2) {
          $options[$name] = $vals
          if ($prm.typeSettings.selectAllValue) { $P[$name] = Format-ParamValue $prm @([string]$prm.typeSettings.selectAllValue) }
          else { $P[$name] = Format-ParamValue $prm $vals }
        } else { $P[$name] = if ($vals.Count) { $vals[0] } else { '' } }
      } elseif ($prm.type -eq 2 -and $prm.jsonData) {
        $opts = @($prm.jsonData | ConvertFrom-Json) | ForEach-Object { if ($_.value) { [string]$_.value } else { [string]$_ } }
        $options[$name] = $opts
        $cur = @($prm.value)
        if ($cur -contains 'value::all') {
          $P[$name] = if ($prm.typeSettings.selectAllValue) { Format-ParamValue $prm @([string]$prm.typeSettings.selectAllValue) } else { Format-ParamValue $prm $opts }
        } else { $P[$name] = Format-ParamValue $prm ($cur | ForEach-Object { [string]$_ }) }
      } else {
        $v = if ($null -ne $prm.value) { @($prm.value) } else { @() }
        $P[$name] = ($v | ForEach-Object { [string]$_ }) -join ','
      }
    }
  }
  $P['Language'] = $Language
  [pscustomobject]@{ P = $P; Options = $options }
}

function Invoke-OneItem {
  param($Tab, $Item, [hashtable]$P, [string[]]$Subs, [string]$Scenario)
  $c = $Item.content; $name = $Item.name
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $isArm = ($c.queryType -eq 12)
  $q = Expand-Tokens $c.query $P
  $unresolved = [regex]::Matches($q, '\{([A-Za-z][A-Za-z0-9_]*)\}') | ForEach-Object { $_.Value } | Select-Object -Unique
  $rec = [ordered]@{ Scenario = $Scenario; Tab = $Tab; Item = $name; Kind = $(if ($isArm) { 'ARM' } else { 'ARG' }); QueryChars = $q.Length
                     Status = 'Skipped'; Rows = $null; Truncated = $false; DurationMs = 0; N429 = 0; Unresolved = ($unresolved -join ' '); Error = '' }
  if ($DryRun) { $rec.Status = $(if ($unresolved) { 'UnresolvedTokens' } else { 'DryRunOK' }); $results.Add([pscustomobject]$rec); return }
  $res = if ($isArm) { Invoke-WithRetry { Invoke-ArmQuery -Json $q } } else { Invoke-WithRetry { Invoke-Arg -Query $q -Subs $Subs } }
  $sw.Stop(); $rec.DurationMs = [int]$sw.ElapsedMilliseconds; $rec.N429 = $res.N429
  if ($res.Ok) {
    if ($isArm) { $rec.Rows = @($res.Value).Count } else { $rec.Rows = @($res.Value.Rows).Count; $rec.Truncated = $res.Value.Truncated }
    $rec.Status = 'OK'
    if ($res.N429 -gt 0) { $rec.Status = 'OK_AFTER_429' }
  } else { $rec.Status = 'FAILED'; $rec.Error = ($res.Error -replace '\s+', ' ').Substring(0, [math]::Min(400, $res.Error.Length)) }
  $results.Add([pscustomobject]$rec)
  Write-Host ('  [{0}] {1,-28} {2,-12} rows={3,-6} {4,6} ms  429={5}' -f $Tab, $name, $rec.Status, $rec.Rows, $rec.DurationMs, $rec.N429)
  return $res
}

function Invoke-Tab {
  param([string]$Tab, $Flat, [hashtable]$P, [string[]]$Subs, [string]$Scenario)
  $P['SelectedTab'] = $Tab
  $queue = @($Flat | Where-Object { ($_.Tab -eq 'Always' -or $_.Tab -eq $Tab) -and $_.Item.type -eq 3 -and (Test-Visible $_.Item $P) })
  # lazy (in-tab) parameters
  foreach ($pi in ($Flat | Where-Object { $_.Tab -eq $Tab -and $_.Item.type -eq 9 })) {
    foreach ($prm in $pi.Item.content.parameters) {
      if ($DryRun -or -not $prm.query) { continue }
      $res = if ($prm.queryType -eq 12) { Invoke-WithRetry { Invoke-ArmQuery -Json (Expand-Tokens $prm.query $P) } } else { Invoke-WithRetry { (Invoke-Arg -Query (Expand-Tokens $prm.query $P) -Subs $Subs).Rows } }
      if ($res.Ok) { $rows = @($res.Value); $first = if ($rows.Count) { ($rows[0].PSObject.Properties | Select-Object -First 1).Name } ; $P[$prm.name] = if ($first) { [string]$rows[0].$first } else { '' } }
    }
  }
  if ($Burst -and -not $DryRun) {
    $tok = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com').Token
    if ($tok -is [securestring]) { $tok = [System.Net.NetworkCredential]::new('', $tok).Password }
    $items = @($queue | ForEach-Object { [pscustomobject]@{ Name = $_.Item.name; IsArm = ($_.Item.content.queryType -eq 12); Text = (Expand-Tokens $_.Item.content.query $P) } })
    Write-Host ("  burst on tab {0}: {1} queries at the same time" -f $Tab, $items.Count)
    $out = $items | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
      $it = $_; $token = $using:tok; $subs = $using:Subs; $max = $using:MaxRetries
      $n429 = 0; $sw = [System.Diagnostics.Stopwatch]::StartNew(); $status = 'OK'; $rows = $null; $err = ''
      $hdr = @{ Authorization = "Bearer $token" }
      for ($a = 0; $a -le $max; $a++) {
        try {
          if ($it.IsArm) {
            $q = $it.Text | ConvertFrom-Json -Depth 50
            $qs = ($q.urlParams | ForEach-Object { "$($_.key)=$($_.value)" }) -join '&'
            $uri = 'https://management.azure.com' + $q.path + '?' + $qs
            $resp = Invoke-WebRequest -Uri $uri -Headers $hdr -Method Get -SkipHttpErrorCheck -ErrorAction Stop
          } else {
            $body = @{ query = $it.Text; options = @{ '$top' = 1000; resultFormat = 'objectArray' } }
            if ($subs) { $body.subscriptions = @($subs) }
            $resp = Invoke-WebRequest -Uri 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Headers $hdr -Method Post -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 10) -SkipHttpErrorCheck -ErrorAction Stop
          }
          if ([int]$resp.StatusCode -eq 429) {
            $n429++; $wait = 0; $ra = $resp.Headers['Retry-After']
            if ($ra) { $wait = [int]@($ra)[0] }
            if ($wait -le 0) { $wait = [math]::Min(30, [math]::Pow(2, $a + 1)) }
            Start-Sleep -Seconds $wait; continue
          }
          if ([int]$resp.StatusCode -ge 400) { $status = 'FAILED'; $err = (([string]$resp.Content) -replace '\s+', ' '); break }
          $j = $resp.Content | ConvertFrom-Json -Depth 50
          $rows = if ($it.IsArm) { @($j.value).Count } else { [int]$j.count }
          if ($n429 -gt 0) { $status = 'OK_AFTER_429' }
          break
        } catch { $status = 'FAILED'; $err = $_.Exception.Message; break }
      }
      if ($a -gt $max -and $status -eq 'OK') { $status = 'FAILED'; $err = 'Still throttled after retries' }
      [pscustomobject]@{ Item = $it.Name; Kind = $(if ($it.IsArm) { 'ARM' } else { 'ARG' }); Chars = $it.Text.Length; Status = $status; Rows = $rows; Ms = [int]$sw.ElapsedMilliseconds; N429 = $n429; Error = $err }
    }
    foreach ($o in @($out)) {
      $results.Add([pscustomobject]@{ Scenario = ($Scenario + '|burst'); Tab = $Tab; Item = $o.Item; Kind = $o.Kind; QueryChars = $o.Chars; Status = $o.Status; Rows = $o.Rows; Truncated = $false; DurationMs = $o.Ms; N429 = $o.N429; Unresolved = ''; Error = $o.Error })
      Write-Host ('  [{0}] {1,-28} {2,-12} rows={3,-6} {4,6} ms  429={5}' -f $Tab, $o.Item, $o.Status, $o.Rows, $o.Ms, $o.N429)
    }
  } else {
    foreach ($q in $queue) { [void](Invoke-OneItem -Tab $Tab -Item $q.Item -P $P -Subs $Subs -Scenario $Scenario) }
  }
}

# ---------- main ----------
if (-not $DryRun) {
  if (-not (Get-AzContext)) { throw 'Run Connect-AzAccount first.' }
  if (-not $Subscriptions) { $Subscriptions = @(Get-AzSubscription | Where-Object State -eq 'Enabled' | ForEach-Object Id) }
} else { if (-not $Subscriptions) { $Subscriptions = @('00000000-0000-0000-0000-000000000000') } }

$flat = @(Get-Flat -Items $wb.items)
$tabs = @($flat | Where-Object { $_.Tab -ne 'Always' } | Select-Object -ExpandProperty Tab -Unique)
if (-not $tabs) { $tabs = @('Always') }
$base = Resolve-Parameters -Subs $Subscriptions
foreach ($k in @($SetParam.Keys)) { $base.P[$k] = [string]$SetParam[$k] }
Write-Host "Workbook: $WorkbookPath | tabs: $($tabs -join ', ') | language: $Language | subscriptions: $($Subscriptions.Count)"

foreach ($t in $tabs) { Invoke-Tab -Tab $t -Flat $flat -P ($base.P.Clone()) -Subs $Subscriptions -Scenario 'default' }

# parameter combinations (multi-select filters)
if ($FilterCombos -ne 'None') {
  $filters = @('OsFilter','StatusFilter','SupportFilter','AutoUpgradeFilter') | Where-Object { $base.Options.ContainsKey($_) }
  $combos = @()
  if ($FilterCombos -eq 'OneFactor') {
    foreach ($f in $filters) { foreach ($v in $base.Options[$f]) { $combos += ,@{ $f = $v } } }
  } else {
    $combos = @(@{})
    foreach ($f in $filters) { $new = @(); foreach ($c in $combos) { foreach ($v in (@('All') + $base.Options[$f])) { $h = $c.Clone(); $h[$f] = $v; $new += ,$h } }; $combos = $new }
  }
  foreach ($c in $combos) {
    $P = $base.P.Clone(); $label = ($c.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ';'
    foreach ($k in $c.Keys) { $P[$k] = if ($c[$k] -eq 'All') { "'All'" } else { "'$($c[$k])'" } }
    foreach ($t in $tabs) { Invoke-Tab -Tab $t -Flat $flat -P $P.Clone() -Subs $Subscriptions -Scenario "combo:$label" }
  }
}

# extension drill-down (agent workbook)
if ($ExtensionDrill -gt 0 -and -not $DryRun) {
  $extItem = ($flat | Where-Object { $_.Item.name -eq 'extensions' } | Select-Object -First 1).Item
  if ($extItem) {
    $rows = (Invoke-Arg -Query (Expand-Tokens $extItem.content.query $base.P) -Subs $Subscriptions).Rows | Select-Object -First $ExtensionDrill
    foreach ($r in $rows) {
      $P = $base.P.Clone(); $P['SelectedTab'] = 'Extensions'
      $P['ExtPublisher'] = [string]$r.Publisher; $P['ExtType'] = [string]$r.ExtensionType; $P['ExtLocation'] = [string]$r.Location; $P['ExtTargetVersion'] = 'latest'
      foreach ($n in 'ExtAvailable','ExtAvailableJson') {
        $pdef = ($flat | Where-Object { $_.Item.type -eq 9 } | ForEach-Object { $_.Item.content.parameters } | Where-Object name -eq $n | Select-Object -First 1)
        $x = Invoke-WithRetry { Invoke-ArmQuery -Json (Expand-Tokens $pdef.query $P) }
        $P[$n] = if ($x.Ok) { (@($x.Value | ForEach-Object { $_.value; $_.v }) | Where-Object { $_ }) -join ',' } else { '' }
      }
      foreach ($q in ($flat | Where-Object { $_.Tab -eq 'Extensions' -and $_.Item.type -eq 3 -and (Test-Visible $_.Item $P) })) {
        [void](Invoke-OneItem -Tab 'Extensions' -Item $q.Item -P $P -Subs $Subscriptions -Scenario "drill:$($P['ExtType'])")
      }
    }
  }
}

# ---------- report ----------
$all = @($results.ToArray())
$csv = Join-Path $OutDir "results_$stamp.csv"
$all | Export-Csv -NoTypeInformation -Path $csv -Encoding utf8
Write-Host "`nResults: $csv"
$all | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize
Write-Host '--- Per tab (default scenario) ---'
$all | Where-Object { $_.Scenario -like 'default*' } | Group-Object Tab | ForEach-Object {
  [pscustomobject]@{ Tab = $_.Name; Queries = $_.Count; Failed = ($_.Group | Where-Object Status -eq 'FAILED').Count
                     Got429 = ($_.Group | Where-Object { $_.N429 -gt 0 }).Count; MaxMs = ($_.Group | Measure-Object DurationMs -Maximum).Maximum
                     Empty = ($_.Group | Where-Object { $_.Status -like 'OK*' -and $_.Rows -eq 0 }).Count; Truncated = ($_.Group | Where-Object Truncated).Count }
} | Format-Table -AutoSize
$bad = @($all | Where-Object { $_.Status -in 'FAILED','UnresolvedTokens' })
if ($bad.Count) { Write-Host 'PROBLEMS:' -ForegroundColor Red; $bad | Select-Object Scenario, Tab, Item, Status, Unresolved, Error | Format-List } else { Write-Host 'No failed queries.' -ForegroundColor Green }
$t429 = ($all | Measure-Object N429 -Sum).Sum
Write-Host "Total 429 responses observed: $t429  (0 expected for -Burst per tab; if > 0 reduce queries per tab or stagger)"
