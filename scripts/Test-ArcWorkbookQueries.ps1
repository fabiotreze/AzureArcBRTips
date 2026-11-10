<#
.SYNOPSIS
  Query validation harness for Azure Workbooks (.workbook JSON) that use Azure Resource Graph (ARG) and ARM (queryType 12).

.DESCRIPTION
  Reads a workbook file, resolves supported static, ARG-backed and ARM-backed parameters,
  then runs visible queries across all tabs / sections against YOUR tenant and writes a CSV + summary:
  status, row count, duration, 429 count, retries, completeness, error text.
  ARG pages are collected up to 10,000 rows. Response metadata determines completeness;
  partial results are INCOMPLETE and fail the run, including when continuation is unavailable.
  This validates queries and simulated selections, not portal rendering or actual navigation clicks.

  Modes
    -DryRun        No Azure call. Parses, resolves tokens, evaluates visibility, counts queries per tab (offline lint).
    (default)      Runs queries sequentially with 429-aware retry (functional test).
    -Burst         Runs all queries of a tab at the same time (like the portal does when a tab opens) to reproduce 429s.
    -FilterCombos  OneFactor | Full | Subsets   Re-runs the tab queries for combinations of the multi-select filters
                   (OsFilter, StatusFilter, SupportFilter, AutoUpgradeFilter) to test parameter combinations.
                   Subsets includes every non-empty subset and the explicit All selection.
    -CacheQueries Reuses identical expanded queries within this run and records CacheHit in the CSV.
    -ExtensionDrill N  Agent workbook only: simulates clicking the first N rows of the Extensions table.
    -AllExtensionTargets  With -ExtensionDrill, tests every version offered by each regional comparison table.

  Requirements: PowerShell 7+, Az.Accounts, Reader on the subscriptions. Read-only against Azure.

  -SetParam overrides are applied before dependent parameters are resolved.
  Exit codes: 1 for failed queries, incomplete results, unresolved tokens or parameter failures; otherwise 0.
  Parameter failures are included in the CSV and the red final summary.
  Parameters awaiting exported row-selection values are reported as skipped, not failed.
  Drill-down parameter resolution remains strict after simulated selection.
  Saida: 1 para falhas de consulta/parametro, resultados incompletos ou tokens nao resolvidos; caso contrario 0.

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
  [ValidateSet('None','OneFactor','Full','Subsets')][string]$FilterCombos = 'None',
  [switch]$CacheQueries,
  [int]$ExtensionDrill = 0,
  [switch]$AllExtensionTargets,
  [hashtable]$SetParam = @{},
  [int]$MaxRetries = 5,
  [int]$ThrottleLimit = 40,
  [string]$OutDir = './workbook-test-results'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$wb = Get-Content -Raw -Path $WorkbookPath -Encoding utf8 | ConvertFrom-Json -Depth 100
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
$queryCache = @{}

# ---------- helpers ----------
function Get-Flat {
  param($Items, $Tab = 'Always', [object[]]$Conditions = @())
  foreach ($it in $Items) {
    $own = if ($it.conditionalVisibilities) { @($it.conditionalVisibilities) } elseif ($it.conditionalVisibility) { @($it.conditionalVisibility) } else { @() }
    $inherited = @($Conditions) + $own
    if ($it.type -eq 12) {
      $t = $Tab
      foreach ($cv in $own) {
        if ($cv.parameterName -eq 'SelectedTab' -and $cv.comparison -in @($null, 'isEqualTo')) { $t = $cv.value }
      }
      Get-Flat -Items $it.content.items -Tab $t -Conditions $inherited
    } else {
      $copy = $it | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
      $copy | Add-Member -NotePropertyName conditionalVisibilities -NotePropertyValue $inherited -Force
      [pscustomobject]@{ Tab = $Tab; Item = $copy }
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
  $all = @(); $skip = $null; $truncated = $false; $seen = @{}
  do {
    $options = @{ '$top' = [math]::Min(1000, 10000 - $all.Count); resultFormat = 'objectArray' }
    if ($skip) { $options.'$skipToken' = $skip }
    $request = @{ query = $Query; options = $options }
    if ($Subs) { $request.subscriptions = @($Subs) }
    $response = Invoke-AzRestMethod -Method POST -Path '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Payload ($request | ConvertTo-Json -Depth 10) -ErrorAction Stop
    if ($response.StatusCode -ne 200) { throw "ARG HTTP $($response.StatusCode): $($response.Content)" }
    $r = $response.Content | ConvertFrom-Json -Depth 100
    if ($null -eq $r.count -or $null -eq $r.totalRecords -or $null -eq $r.data) { throw 'ARG response is missing count, totalRecords or data.' }
    $all += @($r.data)
    $skip = [string]$r.'$skipToken'
    $more = $r.resultTruncated -eq $true -or $r.resultTruncated -eq 'true' -or [long]$r.totalRecords -gt $all.Count -or [bool]$skip
    if ($all.Count -ge 10000 -or ($more -and -not $skip)) { $truncated = $more; break }
    if ($skip) {
      if ($seen.ContainsKey($skip)) { throw 'ARG returned a repeated continuation token.' }
      $seen[$skip] = $true
    }
  } while ($skip)
  [pscustomobject]@{ Rows = $all; Truncated = $truncated }
}

function Invoke-ArmQuery {
  param([string]$Json)
  $q = $Json | ConvertFrom-Json -Depth 50
  if ($q.method -notin @('GET', 'GETARRAY')) { throw "Unsupported read-only ARM method: $($q.method)" }
  $qs = ($q.urlParams | ForEach-Object { "$($_.key)=$($_.value)" }) -join '&'
  $path = $q.path + '?' + $qs
  $pages = @(); $seen = @{}
  do {
    if ($seen.ContainsKey($path)) { throw 'ARM returned a repeated continuation link.' }
    $seen[$path] = $true
    $resp = Invoke-AzRestMethod -Method GET -Path $path -ErrorAction Stop
    if ($resp.StatusCode -ne 200) { throw "HTTP $($resp.StatusCode) $($resp.Content)" }
    $body = $resp.Content | ConvertFrom-Json -Depth 100
    $pages += $body
    $next = if ($body.nextLink) { [string]$body.nextLink } else { [string]$body.'@odata.nextLink' }
    if ($next -and $q.method -ne 'GETARRAY') { throw 'Incomplete ARM result: use GETARRAY to follow nextLink.' }
    if ($next) {
      $uri = [uri]$next
      if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'management.azure.com') { throw 'ARM nextLink must use https://management.azure.com.' }
      $path = $uri.PathAndQuery
    }
    if ($pages.Count -ge 100 -and $next) { throw 'ARM paging exceeded 100 pages.' }
  } while ($next)
  if ($q.method -eq 'GETARRAY') {
    foreach ($page in $pages) {
      if (-not $page.PSObject.Properties['value']) { throw 'ARM GETARRAY requires a value array on every page.' }
    }
    $body = @($pages | ForEach-Object { $_.value })
  }
  $tr = $q.transformers | Select-Object -First 1
  $tp = $tr.settings.tablePath
  $rows = @()
  if ($q.method -eq 'GETARRAY' -and $tp -eq '$.value') { throw 'GETARRAY returns a root array; use $[*], not $.value.' }
  if ($tp -eq '$.value') { $rows = @($body.value) }
  elseif ($tp -eq '$[*]') { $rows = @($body) }
  elseif ($tp -match '^\$\.value\[\?\(@\.agentVersion >= ''(.*)''\)\]$') {
    $min = $Matches[1]; $rows = @($body.value | Where-Object { $_.agentVersion -ge $min })
  } elseif ($tp -eq '$') { $rows = @(,$body) }
  else { throw "Unsupported ARM table JSONPath: $tp" }
  $out = foreach ($r in $rows) {
    $o = [ordered]@{}
    foreach ($c in $tr.settings.columns) {
      $path = $c.path -replace '^\$\.', ''
      if ($c.path -eq '$[*].properties.version') { $o[$c.columnid] = @($body | ForEach-Object { $_.properties.version }) -join ','; continue }
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

function Get-QueryParameterValue {
  param($Param, [object[]]$Rows)
  if (-not $Rows.Count) { return '' }
  $first = ($Rows[0].PSObject.Properties | Select-Object -First 1).Name
  if ($Param.type -eq 2) {
    $values = @($Rows | ForEach-Object { [string]$_.$first })
    if ($Param.multiSelect -and $Param.typeSettings.selectAllValue) {
      return Format-ParamValue $Param @([string]$Param.typeSettings.selectAllValue)
    }
    if ($Param.multiSelect) { return Format-ParamValue $Param $values }
    $selected = @($Rows | Where-Object { $_.selected -eq $true } | Select-Object -First 1)
    if ($selected.Count) { return Format-ParamValue $Param @([string]$selected[0].$first) }
    return Format-ParamValue $Param @($values[0])
  }
  [string]$Rows[0].$first
}

function Invoke-ParameterQuery {
  param($Param, [hashtable]$P, [string[]]$Subs, [switch]$AllowSelectionSkip)
  $query = Expand-Tokens $Param.query $P
  $unresolved = @([regex]::Matches($query, '\{([A-Za-z][A-Za-z0-9_]*)\}') | ForEach-Object Value | Select-Object -Unique)
  if ($unresolved.Count) {
    $unknown = @($unresolved | Where-Object { -not $selectionParameters.ContainsKey($_.Substring(1, $_.Length - 2)) })
    $skipped = $AllowSelectionSkip -and -not $unknown.Count
    return [pscustomobject]@{
      Ok = $false; Value = $null; N429 = 0; Skipped = $skipped; Unresolved = ($unresolved -join ' ')
      Error = $(if ($skipped) { '' } else { "Unresolved parameter tokens: $($unresolved -join ' ')" })
    }
  }
  $key = "parameter|$($Param.queryType)|$($Subs -join ',')|$query"
  if ($CacheQueries -and $queryCache.ContainsKey($key)) { return $queryCache[$key] }
  $result = if ($Param.queryType -eq 12) { Invoke-WithRetry { Invoke-ArmQuery -Json $query } }
  else {
    Invoke-WithRetry {
      $r = Invoke-Arg -Query $query -Subs $Subs
      if ($r.Truncated) { throw "Incomplete ARG parameter result: $($Param.name)" }
      $r.Rows
    }
  }
  if ($CacheQueries -and $result.Ok) { $queryCache[$key] = $result }
  $result
}

function Add-ParameterIssue {
  param($Param, $Result, [string]$Tab, [string]$Scenario)
  $status = if ($Result.Skipped) { 'Skipped (aguarda seleção)' } else { 'FAILED' }
  if ($Result.Skipped) { Write-Host "  parameter $($Param.name): $status - $($Result.Unresolved)" }
  else { Write-Warning "Parameter $($Param.name) failed: $($Result.Error)" }
  $results.Add([pscustomobject]@{
    Scenario = $Scenario; Tab = $Tab; Item = $Param.name; Kind = 'Parameter'
    QueryChars = $Param.query.Length; Status = $status; Rows = $null; Truncated = $false
    DurationMs = 0; N429 = $Result.N429; Unresolved = [string]$Result.Unresolved; Error = $Result.Error
  })
}

function Resolve-Parameters {
  param([hashtable]$Override = @{}, [string[]]$Subs)
  $P = @{}
  $P['Language'] = $Language
  foreach ($k in $Override.Keys) { $P[$k] = [string]$Override[$k] }
  $options = @{}     # param name -> all option values (for filter combos)
  foreach ($pi in (Get-Flat -Items $wb.items | Where-Object { $_.Item.type -eq 9 -and ($_.Tab -ne 'Always' -or (Test-Visible $_.Item $P)) })) {
    foreach ($prm in $pi.Item.content.parameters) {
      $name = $prm.name
      if ($Override.ContainsKey($name)) { continue }
      if ($prm.type -eq 6) { $P[$name] = ($Subs -join ','); continue }
      if ($name -eq 'Language') { continue }
      if ($prm.query -and -not $DryRun) {
        if ($pi.Tab -ne 'Always') { continue }                      # lazy parameters resolve inside their tab
        $res = Invoke-ParameterQuery -Param $prm -P $P -Subs $Subs -AllowSelectionSkip
        if (-not $res.Ok) { Add-ParameterIssue -Param $prm -Result $res -Tab $pi.Tab -Scenario 'parameters'; continue }
        $rows = @($res.Value)
        $first = if ($rows.Count) { ($rows[0].PSObject.Properties | Select-Object -First 1).Name } else { $null }
        $vals = @(if ($first) { $rows | ForEach-Object { [string]$_.$first } })
        Write-Host ('  parameter {0}: {1} value(s)' -f $name, $vals.Count)
        if ($prm.type -eq 2) { $options[$name] = $vals }
        $P[$name] = Get-QueryParameterValue $prm $rows
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
                     Status = 'Skipped'; Rows = $null; Truncated = $false; DurationMs = 0; N429 = 0; CacheHit = $false; Unresolved = ($unresolved -join ' '); Error = '' }
  if (-not $isArm) {
    # ARG allows 3 join and 3 mv-expand operators per query by default (Microsoft Learn: Resource Graph query language limits).
    $bare = [regex]::Replace($q, "'[^']*'", "''")
    $joins = ([regex]::Matches($bare, '\|\s*join\b')).Count
    $expands = ([regex]::Matches($bare, '\|\s*mv-expand\b')).Count
    if ($joins -gt 3 -or $expands -gt 3) {
      $rec.Status = 'FAILED'; $rec.Error = "ARG operator limit exceeded: join=$joins, mv-expand=$expands (max 3 each)."
      $results.Add([pscustomobject]$rec); return
    }
  }
  if ($DryRun -or $unresolved) { $rec.Status = $(if ($unresolved) { 'UnresolvedTokens' } else { 'DryRunOK' }); $results.Add([pscustomobject]$rec); return }
  $key = "$isArm|$($Subs -join ',')|$q"
  if ($CacheQueries -and $queryCache.ContainsKey($key)) { $res = $queryCache[$key]; $rec.CacheHit = $true }
  else {
    $res = if ($isArm) { Invoke-WithRetry { Invoke-ArmQuery -Json $q } } else { Invoke-WithRetry { Invoke-Arg -Query $q -Subs $Subs } }
    if ($CacheQueries -and $res.Ok) { $queryCache[$key] = $res }
  }
  $sw.Stop(); $rec.DurationMs = [int]$sw.ElapsedMilliseconds; $rec.N429 = $res.N429
  if ($res.Ok) {
    if ($isArm) { $rec.Rows = @($res.Value).Count } else { $rec.Rows = @($res.Value.Rows).Count; $rec.Truncated = $res.Value.Truncated }
    $rec.Status = 'OK'
    if ($res.N429 -gt 0) { $rec.Status = 'OK_AFTER_429' }
    if ($rec.Truncated) { $rec.Status = 'INCOMPLETE'; $rec.Error = 'ARG returned a partial result; completeness is not verified.' }
  } else {
    $rec.Status = 'FAILED'
    $errorText = $res.Error -replace '\s+', ' '
    $rec.Error = $errorText.Substring(0, [math]::Min(400, $errorText.Length))
  }
  $results.Add([pscustomobject]$rec)
  Write-Host ('  [{0}] {1,-28} {2,-12} rows={3,-6} {4,6} ms  429={5}' -f $Tab, $name, $rec.Status, $rec.Rows, $rec.DurationMs, $rec.N429)
  return $res
}

function Invoke-Tab {
  param([string]$Tab, $Flat, [hashtable]$P, [string[]]$Subs, [string]$Scenario)
  $P['SelectedTab'] = $Tab
  # lazy (in-tab) parameters
  foreach ($pi in ($Flat | Where-Object { $Tab -ne 'Always' -and $_.Tab -eq $Tab -and $_.Item.type -eq 9 -and (Test-Visible $_.Item $P) })) {
    foreach ($prm in $pi.Item.content.parameters) {
      if ($DryRun -or -not $prm.query -or $SetParam.ContainsKey($prm.name)) { continue }
      $res = Invoke-ParameterQuery -Param $prm -P $P -Subs $Subs -AllowSelectionSkip
      if ($res.Ok) { $P[$prm.name] = Get-QueryParameterValue $prm @($res.Value) }
      else { $P.Remove($prm.name); Add-ParameterIssue -Param $prm -Result $res -Tab $Tab -Scenario $Scenario }
    }
  }
  $queue = @($Flat | Where-Object { ($_.Tab -eq 'Always' -or $_.Tab -eq $Tab) -and $_.Item.type -eq 3 -and (Test-Visible $_.Item $P) })
  if ($Burst -and -not $DryRun) {
    $items = @(
      foreach ($q in $queue) {
        $text = Expand-Tokens $q.Item.content.query $P
        if ($text -match '\{([A-Za-z][A-Za-z0-9_]*)\}') {
          [void](Invoke-OneItem -Tab $Tab -Item $q.Item -P $P -Subs $Subs -Scenario ($Scenario + '|burst'))
        } else {
          [pscustomobject]@{ Name = $q.Item.name; IsArm = ($q.Item.content.queryType -eq 12); Text = $text }
        }
      }
    )
    if (-not $items.Count) { return }
    $tok = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com').Token
    if ($tok -is [securestring]) { $tok = [System.Net.NetworkCredential]::new('', $tok).Password }
    Write-Host ("  burst on tab {0}: {1} queries at the same time" -f $Tab, $items.Count)
    $definitions = foreach ($name in 'Invoke-Arg','Invoke-ArmQuery','Invoke-WithRetry') {
      "function $name { $((Get-Item "function:$name").Definition) }"
    }
    $definitions = $definitions -join "`n"
    $out = $items | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
      $it = $_; $token = $using:tok; $subs = $using:Subs; $MaxRetries = $using:MaxRetries
      . ([scriptblock]::Create($using:definitions))
      function Invoke-AzRestMethod {
        param($Method, $Path, $Payload, $ErrorAction)
        $arguments = @{
          Uri = 'https://management.azure.com' + $Path
          Headers = @{ Authorization = "Bearer $token" }
          Method = $Method; SkipHttpErrorCheck = $true; ErrorAction = 'Stop'
        }
        if ($Payload) { $arguments.Body = $Payload; $arguments.ContentType = 'application/json' }
        $response = Invoke-WebRequest @arguments
        if ([int]$response.StatusCode -eq 429) {
          $retry = [string]($response.Headers['Retry-After'] | Select-Object -First 1)
          throw "HTTP 429 Retry-After: $retry"
        }
        [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Content = [string]$response.Content }
      }
      $sw = [Diagnostics.Stopwatch]::StartNew()
      $res = if ($it.IsArm) { Invoke-WithRetry { Invoke-ArmQuery $it.Text } } else { Invoke-WithRetry { Invoke-Arg $it.Text $subs } }
      $status = 'FAILED'; $rows = $null; $truncated = $false; $err = $res.Error
      if ($res.Ok) {
        $rows = if ($it.IsArm) { @($res.Value).Count } else { @($res.Value.Rows).Count }
        $truncated = -not $it.IsArm -and $res.Value.Truncated
        $status = if ($truncated) { 'INCOMPLETE' } elseif ($res.N429) { 'OK_AFTER_429' } else { 'OK' }
        if ($truncated) { $err = 'ARG returned a partial result; completeness is not verified.' }
      }
      [pscustomobject]@{ Item = $it.Name; Kind = $(if ($it.IsArm) { 'ARM' } else { 'ARG' }); Chars = $it.Text.Length; Status = $status; Rows = $rows; Truncated = $truncated; Ms = [int]$sw.ElapsedMilliseconds; N429 = $res.N429; Error = $err }
    }
    foreach ($o in @($out)) {
      $results.Add([pscustomobject]@{ Scenario = ($Scenario + '|burst'); Tab = $Tab; Item = $o.Item; Kind = $o.Kind; QueryChars = $o.Chars; Status = $o.Status; Rows = $o.Rows; Truncated = $o.Truncated; DurationMs = $o.Ms; N429 = $o.N429; CacheHit = $false; Unresolved = ''; Error = $o.Error })
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
$selectionParameters = @{}
foreach ($query in ($flat | Where-Object { $_.Item.type -eq 3 })) {
  $content = $query.Item.content
  foreach ($export in $content.exportedParameters) {
    if ($export.fieldName -and $export.parameterName) { $selectionParameters[$export.parameterName] = $true }
  }
  if ($content.exportFieldName -and $content.exportParameterName) { $selectionParameters[$content.exportParameterName] = $true }
}
$tabs = @($flat | Where-Object { $_.Tab -ne 'Always' } | Select-Object -ExpandProperty Tab -Unique)
if (-not $tabs) { $tabs = @('Always') }
$base = Resolve-Parameters -Override $SetParam -Subs $Subscriptions
Write-Host "Workbook: $WorkbookPath | tabs: $($tabs -join ', ') | language: $($base.P['Language']) | subscriptions: $($Subscriptions.Count)"

foreach ($t in $tabs) { Invoke-Tab -Tab $t -Flat $flat -P ($base.P.Clone()) -Subs $Subscriptions -Scenario 'default' }

# parameter combinations (multi-select filters)
if ($FilterCombos -ne 'None') {
  $filters = @('OsFilter','StatusFilter','SupportFilter','AutoUpgradeFilter') | Where-Object { $base.Options.ContainsKey($_) }
  $combos = @()
  if ($FilterCombos -eq 'OneFactor') {
    foreach ($f in $filters) { foreach ($v in $base.Options[$f]) { $combos += ,@{ $f = $v } } }
  } else {
    $combos = @(@{})
    foreach ($f in $filters) {
      $values = @($base.Options[$f] | Select-Object -Unique)
      $selections = @(@('All'))
      if ($FilterCombos -eq 'Subsets') {
        if ($values.Count -gt 16) { throw "Too many options for exhaustive subsets: $f ($($values.Count))." }
        for ($mask = 1; $mask -lt [math]::Pow(2, $values.Count); $mask++) {
          $subset = @(for ($bit = 0; $bit -lt $values.Count; $bit++) { if ($mask -band (1 -shl $bit)) { $values[$bit] } })
          $selections += ,$subset
        }
      } else { foreach ($v in $values) { $selections += ,@($v) } }
      $new = @()
      foreach ($c in $combos) { foreach ($selection in $selections) { $h = $c.Clone(); $h[$f] = $selection; $new += ,$h } }
      $combos = $new
    }
  }
  foreach ($c in $combos) {
    $P = $base.P.Clone(); $label = ($c.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ';'
    foreach ($k in $c.Keys) {
      $definition = $flat | Where-Object { $_.Item.type -eq 9 } | ForEach-Object { $_.Item.content.parameters } | Where-Object name -eq $k | Select-Object -First 1
      $P[$k] = Format-ParamValue $definition @($c[$k])
    }
    foreach ($t in $tabs) { Invoke-Tab -Tab $t -Flat $flat -P $P.Clone() -Subs $Subscriptions -Scenario "combo:$label" }
  }
}

# extension drill-down (agent workbook)
if ($ExtensionDrill -gt 0 -and -not $DryRun) {
  $extItem = ($flat | Where-Object { $_.Item.name -eq 'extensions' } | Select-Object -First 1).Item
  if ($extItem) {
    $drillResult = Invoke-Arg -Query (Expand-Tokens $extItem.content.query $base.P) -Subs $Subscriptions
    if ($drillResult.Truncated) { throw 'Incomplete extension selection list.' }
    $rows = $drillResult.Rows | Select-Object -First $ExtensionDrill
    foreach ($r in $rows) {
      $P = $base.P.Clone(); $P['SelectedTab'] = 'Extensions'
      $P['ExtPublisher'] = [string]$r.Publisher; $P['ExtType'] = [string]$r.ExtensionType; $P['ExtLocation'] = [string]$r.Location; $P['ExtTargetVersion'] = 'latest'
      foreach ($n in 'ExtAvailable','ExtAvailableJson') {
        if ($SetParam.ContainsKey($n)) { continue }
        $pdef = ($flat | Where-Object { $_.Item.type -eq 9 } | ForEach-Object { $_.Item.content.parameters } | Where-Object name -eq $n | Select-Object -First 1)
        $x = Invoke-ParameterQuery -Param $pdef -P $P -Subs $Subscriptions
        if ($x.Ok) { $P[$n] = (@($x.Value | ForEach-Object { $_.value; $_.v }) | Where-Object { $_ }) -join ',' }
        else { $P.Remove($n); Add-ParameterIssue -Param $pdef -Result $x -Tab 'Extensions' -Scenario "drill:$($P['ExtType'])" }
      }
      $targets = @()
      foreach ($q in ($flat | Where-Object { $_.Tab -eq 'Extensions' -and $_.Item.type -eq 3 -and (Test-Visible $_.Item $P) })) {
        $selectionResult = Invoke-OneItem -Tab 'Extensions' -Item $q.Item -P $P -Subs $Subscriptions -Scenario "drill:$($P['ExtLocation']):$($P['ExtType'])"
        if ($AllExtensionTargets -and $q.Item.name -eq 'ext-available' -and $selectionResult.Ok) {
          $targets = @($selectionResult.Value.Rows | ForEach-Object Version | Where-Object { $_ } | Select-Object -Unique)
        }
      }
      foreach ($target in $targets) {
        $P['ExtTargetVersion'] = [string]$target
        foreach ($q in ($flat | Where-Object { $_.Item.name -eq 'ext-detail' -and (Test-Visible $_.Item $P) })) {
          [void](Invoke-OneItem -Tab 'Extensions' -Item $q.Item -P $P -Subs $Subscriptions -Scenario "target:$($P['ExtLocation']):$($P['ExtType']):$target")
        }
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
$waiting = @($all | Where-Object Status -eq 'Skipped (aguarda seleção)')
if ($waiting.Count) {
  Write-Host '--- Awaiting row selection / Aguarda seleção ---'
  Write-Host ($waiting | Select-Object Scenario, Tab, Item, Status, Unresolved | Format-Table -AutoSize | Out-String)
}
$bad = @($all | Where-Object { $_.Status -in 'FAILED','UnresolvedTokens','INCOMPLETE' })
if ($bad.Count) {
  Write-Host 'PROBLEMS:' -ForegroundColor Red
  Write-Host ($bad | Select-Object Scenario, Tab, Kind, Item, Status, Unresolved, Error | Format-List | Out-String) -ForegroundColor Red
} else { Write-Host 'No failed queries or parameter failures.' -ForegroundColor Green }
$t429 = ($all | Measure-Object N429 -Sum).Sum
Write-Host "Total 429 responses observed: $t429  (0 expected for -Burst per tab; if > 0 reduce queries per tab or stagger)"
if ($bad.Count) { exit 1 }
exit 0
