#Requires -Version 7.0
<#
.SYNOPSIS
  Offline regression tests with mocked Azure commands; no Azure connection or Pester required.
  Testes de regressao offline com mocks; sem conexao ao Azure ou dependencia do Pester.
  Status assertions use UTF-8 CSV; console checks use ASCII markers only.
  Status validado pelo CSV UTF-8; verificacoes do console usam apenas marcadores ASCII.
.EXAMPLE
  pwsh -NoProfile -File .\scripts\Test-ArcWorkbookQueries.Tests.ps1
#>
[CmdletBinding()]
param(
  [switch]$Worker,
  [string]$Case,
  [string]$TestRoot
)

$ErrorActionPreference = 'Stop'
$harness = Join-Path $PSScriptRoot 'Test-ArcWorkbookQueries.ps1'

if ($Worker) {
  function Write-Host {
    param($Object, $ForegroundColor)
    if ($ForegroundColor -eq 'Red') { [Console]::WriteLine("<Red>$Object</Red>") }
    else { [Console]::WriteLine([string]$Object) }
  }
  function Get-AzContext { [pscustomobject]@{ Mock = $true } }
  function Get-AzSubscription { throw 'Unexpected subscription discovery' }
  function Get-AzAccessToken { throw 'Azure token requests are disabled in tests' }
  function Invoke-WebRequest { throw 'HTTP requests are disabled in tests' }
  function Invoke-RestMethod { throw 'HTTP requests are disabled in tests' }
  function Search-AzGraph {
    param($Query, $First, $Subscription, $SkipToken, $ErrorAction)
    if ($Query -eq 'fail-whitespace') { throw ('Mock error:' + (' ' * 500) + 'details') }
    if ($Query -like 'fail-*') { [Console]::WriteLine("FAILED_PARAMETER_QUERY=$Query"); throw "Mock error: $Query" }
    if ($Query -like 'derive:*') {
      [pscustomobject]@{ value = $Query.Substring(7) }
      if ($Case -eq 'override-dependent') { [pscustomobject]@{ value = 'second row' } }
    } elseif ($Query -like 'observe:*') {
      [Console]::WriteLine("OBSERVED=$($Query.Substring(8))")
      [pscustomobject]@{ value = $Query.Substring(8) }
    } elseif ($Query -eq 'extensions') {
      [pscustomobject]@{ Publisher = 'MockPublisher'; ExtensionType = 'MockType'; Location = 'MockLocation' }
    } elseif ($Query -eq 'choices') {
      [pscustomobject]@{ value = 'first'; selected = $false }
      [pscustomobject]@{ value = 'chosen'; selected = $true }
    } elseif ($Case -like 'workbook-*') {
      [pscustomobject]@{ value = '1.69' }
    } elseif ($Query -ne 'empty') {
      [pscustomobject]@{ value = 'ok' }
    }
  }
  function Invoke-AzRestMethod {
    param($Method, $Path, $Payload, $ErrorAction)
    if ($Path -like '/providers/Microsoft.ResourceGraph/resources?*') {
      $request = $Payload | ConvertFrom-Json
      $query = $request.query
      [Console]::WriteLine("ARG_CALL=$query")
      $data = @(Search-AzGraph -Query $query)
      $total = $data.Count; $truncated = $false; $skip = $null
      switch ($query) {
        'paged' {
          $data = if ($request.options.'$skipToken') { @(@{ value = 'third' }) } else { @(@{ value = 'first' }, @{ value = 'second' }) }
          $total = 3
          if (-not $request.options.'$skipToken') { $skip = 'page2'; $truncated = $true }
        }
        'incomplete' { $total = 1001; $truncated = $true }
        'exact-cap' {
          $offset = [int]$request.options.'$skipToken'
          $data = @(1..1000 | ForEach-Object { @{ value = $offset + $_ } }); $total = 10000
          if ($offset -lt 9000) { $skip = [string]($offset + 1000); $truncated = $true }
        }
        'repeated-token' { $total = 10000; $skip = 'repeat'; $truncated = $true }
      }
      $body = @{ count = $data.Count; totalRecords = $total; data = $data; resultTruncated = $truncated }
      if ($skip) { $body.'$skipToken' = $skip }
      return [pscustomobject]@{ StatusCode = 200; Content = ($body | ConvertTo-Json -Depth 20) }
    }
    [Console]::WriteLine("ARM_PATH=$Path")
    if ($Case -eq 'selection-drill-failure' -and $Path -like '/selected/*') { throw 'Mock selected extension failure' }
    if ($Path -like '/fail-*') { throw "Mock error: $Path" }
    if ($Case -eq 'arm-array-paged-aggregate') {
      $body = @{ value = @(@{ properties = @{ version = $(if ($Path -like '/catalog*') { '1.68' } else { '1.69' }) } }) }
      if ($Path -like '/catalog*') { $body.nextLink = 'https://management.azure.com/next' }
      return [pscustomobject]@{ StatusCode = 200; Content = ($body | ConvertTo-Json -Depth 10) }
    }
    if ($Case -like 'arm-paging-*') {
      $body = @{ value = @(@{ value = 'first' }) }
      if ($Path -like '/catalog*' -or $Case -eq 'arm-paging-cycle') { $body.nextLink = 'https://management.azure.com/next' }
      return [pscustomobject]@{ StatusCode = 200; Content = ($body | ConvertTo-Json -Depth 10) }
    }
    [pscustomobject]@{
      StatusCode = 200
      Content = '{"osType":"windows","agentVersion":"1.69","downloadLink":"https://example.com/agent","value":[{"value":"1.69","agentVersion":"1.69","properties":{"version":"1.69"}}]}'
    }
  }
  function New-Parameter($Name, $Query, $Value, $QueryType = 1) {
    [pscustomobject]@{ name = $Name; type = 1; query = $Query; queryType = $QueryType; value = $Value }
  }
  function New-Query($Query, $Name = 'query') {
    [pscustomobject]@{ type = 3; name = $Name; content = @{ query = $Query; queryType = 1 } }
  }
  function New-ArmQuery($Path) {
    @{
      method = 'GET'; path = $Path; urlParams = @()
      transformers = @(@{
        settings = @{ tablePath = '$.value'; columns = @(@{ path = '$.value'; columnid = 'value' }) }
      })
    } | ConvertTo-Json -Depth 10 -Compress
  }

  $parameters = @()
  $items = @()
  $arguments = @{ MaxRetries = 0 }
  switch ($Case) {
    'success' { $items = @(New-Query 'ok') }
    'empty-success' { $items = @(New-Query 'empty') }
    'arg-paged' { $items = @(New-Query 'paged') }
    'arg-incomplete' { $items = @(New-Query 'incomplete') }
    'arg-exact-cap' { $items = @(New-Query 'exact-cap') }
    'arg-repeated-token' { $items = @(New-Query 'repeated-token') }
    'arg-parameter-incomplete' { $parameters = @(New-Parameter 'Incomplete' 'incomplete') }
    'cached-query' {
      $items = @((New-Query 'ok' 'first'), (New-Query 'ok' 'second'))
      $arguments.CacheQueries = $true
    }
    'subset-combinations' {
      $parameters = @([pscustomobject]@{
        name = 'OsFilter'; type = 2; multiSelect = $true; quote = "'"; delimiter = ','
        value = @('value::all'); jsonData = '["windows","linux"]'; typeSettings = @{ selectAllValue = 'All' }
      })
      $items = @(New-Query 'observe:{OsFilter}')
      $arguments.FilterCombos = 'Subsets'
    }
    'nested-language' {
      $items = @([pscustomobject]@{
        type = 12; conditionalVisibility = @{ parameterName = 'Language'; comparison = 'isEqualTo'; value = 'EN' }
        content = @{ items = @(New-Query 'fail-hidden') }
      })
      $arguments.Language = 'PT'
    }
    { $_ -like 'arm-paging-*' } {
      $query = New-ArmQuery '/catalog'
      if ($Case -ne 'arm-paging-get') {
        $query = $query.Replace('"GET"', '"GETARRAY"')
        if ($Case -ne 'arm-paging-envelope') { $query = $query.Replace('"tablePath":"$.value"', '"tablePath":"$[*]"') }
      }
      $items = @([pscustomobject]@{ type = 3; name = 'arm'; content = @{ queryType = 12; query = $query } })
    }
    'arm-array-single-page' {
      $query = (New-ArmQuery '/single').Replace('"GET"', '"GETARRAY"').Replace('"tablePath":"$.value"', '"tablePath":"$[*]"')
      $parameters = @(New-Parameter 'Catalog' $query '' 12)
      $items = @(New-Query 'observe:{Catalog}')
    }
    { $_ -in 'arm-array-aggregate','arm-array-paged-aggregate' } {
      $query = New-ArmQuery $(if ($Case -eq 'arm-array-paged-aggregate') { '/catalog' } else { '/single' }) | ConvertFrom-Json -Depth 20
      $query.method = 'GETARRAY'
      $query.transformers[0].settings.tablePath = '$'
      $query.transformers[0].settings.columns[0].path = '$[*].properties.version'
      $parameters = @(New-Parameter 'Catalog' ($query | ConvertTo-Json -Depth 20 -Compress) '' 12)
      $items = @(New-Query 'observe:{Catalog}')
    }
    'failed-query' { $items = @(New-Query 'fail-query') }
    'failed-query-whitespace' { $items = @(New-Query 'fail-whitespace') }
    'unresolved-dry' { $items = @(New-Query '{Missing}'); $arguments.DryRun = $true }
    'unresolved-live' { $items = @(New-Query '{Missing}') }
    'operator-limit-dry' { $items = @(New-Query ('T | join (A) on k | join (B) on k | join (C) on k | join (D) on k')); $arguments.DryRun = $true }
    'operator-limit-ok' { $items = @(New-Query ("T | where x == '| join | join | join | join' | join (A) on k | mv-expand y")); $arguments.DryRun = $true }
    'unresolved-burst' { $items = @(New-Query '{Missing}'); $arguments.Burst = $true }
    'override-dependent' {
      $parameters = @(
        (New-Parameter 'LatestOverride' $null '1.69'),
        (New-Parameter 'Derived' 'derive:{LatestOverride}')
      )
      $items = @(New-Query 'observe:{Derived}')
      $arguments.SetParam = @{ LatestOverride = '1.70' }
    }
    'scalar-arg' {
      $parameters = @(New-Parameter 'Derived' 'derive:1.69')
      $items = @(New-Query 'observe:{Derived}')
    }
    'scalar-arm' {
      $parameters = @(New-Parameter 'Derived' (New-ArmQuery '/ok') $null 12)
      $items = @(New-Query 'observe:{Derived}')
    }
    'selected-dropdown' {
      $parameters = @([pscustomobject]@{ name = 'Choice'; type = 2; query = 'choices'; queryType = 1 })
      $items = @(New-Query 'observe:{Choice}')
    }
    'lazy-selected-dropdown' {
      $items = @([pscustomobject]@{
        type = 12; conditionalVisibility = @{ parameterName = 'SelectedTab'; comparison = 'isEqualTo'; value = 'MockTab' }
        content = @{ items = @(
          [pscustomobject]@{ type = 9; content = @{ parameters = @([pscustomobject]@{ name = 'Choice'; type = 2; query = 'choices'; queryType = 1 }) } },
          (New-Query 'observe:{Choice}')
        ) }
      })
    }
    'global-arg-failure' { $parameters = @(New-Parameter 'GlobalFailure' 'fail-global') }
    'global-arm-failure' { $parameters = @(New-Parameter 'GlobalFailure' (New-ArmQuery '/fail-global') $null 12) }
    'parameter-dependency-failure' {
      $parameters = @(
        (New-Parameter 'GlobalFailure' 'fail-global'),
        (New-Parameter 'Dependent' 'derive:{GlobalFailure}')
      )
      $items = @(New-Query 'observe:{Dependent}')
    }
    { $_ -in 'selection-default-multi', 'selection-default-single', 'selection-unknown' } {
      $selection = New-Query 'ok' 'selection-source'
      if ($Case -eq 'selection-default-single') {
        $selection.content.exportParameterName = 'ClickedBuild'
        $selection.content.exportFieldName = 'Version'
        $parameters = @(New-Parameter 'Waiting' 'derive:{ClickedBuild}')
      } else {
        $selection.content.exportedParameters = @(
          @{ fieldName = 'Region'; parameterName = 'ClickedRegion' },
          @{ fieldName = 'Publisher'; parameterName = 'ClickedPublisher' }
        )
        $query = 'derive:{ClickedRegion}/{ClickedPublisher}'
        if ($Case -eq 'selection-unknown') { $query += '/{Missing}' }
        $parameters = @(New-Parameter 'Waiting' $query)
      }
      $items = @($selection)
    }
    { $_ -in 'selection-lazy-default', 'selection-drill-success', 'selection-drill-failure', 'selection-drill-unresolved' } {
      $selection = New-Query 'extensions' 'extensions'
      $selection.content.exportedParameters = @(
        @{ fieldName = 'Location'; parameterName = 'ExtLocation' },
        @{ fieldName = 'Publisher'; parameterName = 'ExtPublisher' },
        @{ fieldName = 'ExtensionType'; parameterName = 'ExtType' }
      )
      $path = '/selected/{ExtLocation}/{ExtPublisher}/{ExtType}'
      if ($Case -eq 'selection-drill-unresolved') {
        $selection.content.exportedParameters += @{ fieldName = 'Other'; parameterName = 'UnfilledSelection' }
        $path += '/{UnfilledSelection}'
      }
      $items = @([pscustomobject]@{
        type = 12; conditionalVisibility = @{ parameterName = 'SelectedTab'; value = 'Extensions' }
        content = @{ items = @(
          [pscustomobject]@{ type = 9; content = @{ parameters = @(
            (New-Parameter 'ExtAvailable' (New-ArmQuery $path) $null 12),
            (New-Parameter 'ExtAvailableJson' (New-ArmQuery $path) $null 12)
          ) } },
          $selection
        ) }
      })
      if ($Case -like 'selection-drill-*') { $arguments.ExtensionDrill = 1 }
    }
    { $_ -like 'workbook-*' } {
      $project = if ($Case -like 'workbook-agent-*') { 'arc-agent-support' } else { 'arc-sql-payg-readiness' }
      $workbookPath = Join-Path $PSScriptRoot "..\workbooks\$project-workbook.json"
      $arguments.Language = if ($Case -like '*-en') { 'EN' } else { 'PT' }
      if ($Case -like '*-dry-*') { $arguments.DryRun = $true }
    }
    { $_ -in 'lazy-arg-failure', 'lazy-arm-failure', 'lazy-override' } {
      $parameter = if ($Case -eq 'lazy-arm-failure') {
        New-Parameter 'LazyFailure' (New-ArmQuery '/fail-lazy') $null 12
      } else { New-Parameter 'LazyFailure' 'fail-lazy' }
      $items = @([pscustomobject]@{
        type = 12; conditionalVisibility = @{ parameterName = 'SelectedTab'; value = 'MockTab' }
        content = @{ items = @(
          [pscustomobject]@{ type = 9; content = @{ parameters = @($parameter) } },
          (New-Query 'observe:{LazyFailure}')
        ) }
      })
      if ($Case -eq 'lazy-override') { $arguments.SetParam = @{ LazyFailure = 'manual' } }
    }
    'drill-failure' {
      $items = @([pscustomobject]@{
        type = 12; conditionalVisibility = @{ parameterName = 'SelectedTab'; value = 'Extensions' }
        content = @{ items = @(
          [pscustomobject]@{ type = 9; content = @{ parameters = @(
            (New-Parameter 'ExtAvailable' (New-ArmQuery '/fail-drill') $null 12),
            (New-Parameter 'ExtAvailableJson' (New-ArmQuery '/fail-drill') $null 12)
          ) } },
          (New-Query 'extensions' 'extensions')
        ) }
      })
      $arguments.ExtensionDrill = 1
    }
    default { throw "Unknown test case: $Case" }
  }
  if ($items.Count -and -not @($items | Where-Object type -eq 12).Count) {
    $items = @([pscustomobject]@{
      type = 12; conditionalVisibility = @{ parameterName = 'SelectedTab'; value = 'MockTab' }
      content = @{ items = $items }
    })
  }
  if ($Case -notlike 'workbook-*') {
    $workbook = @{ items = @([pscustomobject]@{ type = 9; content = @{ parameters = $parameters } }) + $items }
    $workbookPath = Join-Path $TestRoot 'workbook.json'
    if (Test-Path -LiteralPath $workbookPath) { throw "Fixture already exists: $workbookPath" }
    $workbook | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $workbookPath -Encoding utf8
  }
  & $harness -WorkbookPath $workbookPath -Subscriptions '00000000-0000-0000-0000-000000000000' -OutDir $TestRoot @arguments
  exit $LASTEXITCODE
}

$cases = @(
  @{ Name = 'success'; Exit = 0 },
  @{ Name = 'empty-success'; Exit = 0 },
  @{ Name = 'arg-paged'; Exit = 0; Rows = 3 },
  @{ Name = 'arg-incomplete'; Exit = 1; Status = 'INCOMPLETE' },
  @{ Name = 'arg-exact-cap'; Exit = 0; Rows = 10000 },
  @{ Name = 'arg-repeated-token'; Exit = 1; Status = 'FAILED' },
  @{ Name = 'arg-parameter-incomplete'; Exit = 1; Parameter = 'Incomplete' },
  @{ Name = 'cached-query'; Exit = 0; Required = 'ARG_CALL=ok'; RequiredCount = 1; CacheHits = 1 },
  @{ Name = 'subset-combinations'; Exit = 0; Required = "OBSERVED='windows','linux'"; QueryCount = 5 },
  @{ Name = 'nested-language'; Exit = 0; Forbidden = 'ARG_CALL=fail-hidden' },
  @{ Name = 'arm-paging-get'; Exit = 1; Status = 'FAILED' },
  @{ Name = 'arm-paging-array'; Exit = 0; Rows = 2 },
  @{ Name = 'arm-paging-envelope'; Exit = 1; Status = 'FAILED' },
  @{ Name = 'arm-paging-cycle'; Exit = 1; Status = 'FAILED' },
  @{ Name = 'arm-array-single-page'; Exit = 0; Observed = '1.69' },
  @{ Name = 'arm-array-aggregate'; Exit = 0; Observed = '1.69' },
  @{ Name = 'arm-array-paged-aggregate'; Exit = 0; Observed = '1.68,1.69' },
  @{ Name = 'failed-query'; Exit = 1; Status = 'FAILED' },
  @{ Name = 'failed-query-whitespace'; Exit = 1; Status = 'FAILED' },
  @{ Name = 'unresolved-dry'; Exit = 1; Status = 'UnresolvedTokens' },
  @{ Name = 'unresolved-live'; Exit = 1; Status = 'UnresolvedTokens' },
  @{ Name = 'operator-limit-dry'; Exit = 1; Status = 'FAILED' },
  @{ Name = 'operator-limit-ok'; Exit = 0; Status = 'DryRunOK' },
  @{ Name = 'unresolved-burst'; Exit = 1; Status = 'UnresolvedTokens' },
  @{ Name = 'override-dependent'; Exit = 0; Observed = '1.70' },
  @{ Name = 'scalar-arg'; Exit = 0; Observed = '1.69' },
  @{ Name = 'scalar-arm'; Exit = 0; Observed = '1.69' },
  @{ Name = 'selected-dropdown'; Exit = 0; Observed = 'chosen' },
  @{ Name = 'lazy-selected-dropdown'; Exit = 0; Observed = 'chosen' },
  @{ Name = 'global-arg-failure'; Exit = 1; Parameter = 'GlobalFailure' },
  @{ Name = 'global-arm-failure'; Exit = 1; Parameter = 'GlobalFailure' },
  @{ Name = 'parameter-dependency-failure'; Exit = 1; Parameter = 'Dependent'; Status = 'UnresolvedTokens' },
  @{ Name = 'lazy-arg-failure'; Exit = 1; Parameter = 'LazyFailure' },
  @{ Name = 'lazy-arm-failure'; Exit = 1; Parameter = 'LazyFailure' },
  @{ Name = 'lazy-override'; Exit = 0; Observed = 'manual'; Forbidden = 'FAILED_PARAMETER_QUERY=' },
  @{ Name = 'drill-failure'; Exit = 1; Parameter = 'ExtAvailable'; Scenario = 'drill:MockType' },
  @{ Name = 'selection-default-multi'; Exit = 0; Skipped = 1; Forbidden = '<Red>' },
  @{ Name = 'selection-default-single'; Exit = 0; Skipped = 1; Forbidden = '<Red>' },
  @{ Name = 'selection-lazy-default'; Exit = 0; Skipped = 2; Forbidden = '<Red>' },
  @{ Name = 'selection-unknown'; Exit = 1; Parameter = 'Waiting' },
  @{ Name = 'selection-drill-success'; Exit = 0; Skipped = 2; Required = 'ARM_PATH=/selected/MockLocation/MockPublisher/MockType'; RequiredCount = 2; Forbidden = '<Red>' },
  @{ Name = 'selection-drill-failure'; Exit = 1; Skipped = 2; Parameter = 'ExtAvailable'; Scenario = 'drill:MockType' },
  @{ Name = 'selection-drill-unresolved'; Exit = 1; Skipped = 2; Parameter = 'ExtAvailable'; Scenario = 'drill:MockType' },
  @{ Name = 'workbook-agent-dry-pt'; Exit = 0; Status = 'DryRunOK'; Forbidden = '<Red>' },
  @{ Name = 'workbook-agent-dry-en'; Exit = 0; Status = 'DryRunOK'; Forbidden = '<Red>' },
  @{ Name = 'workbook-agent-default-pt'; Exit = 0; Status = 'OK'; Forbidden = '<Red>' },
  @{ Name = 'workbook-agent-default-en'; Exit = 0; Status = 'OK'; Forbidden = '<Red>' },
  @{ Name = 'workbook-sql-dry-pt'; Exit = 0; Status = 'DryRunOK'; Forbidden = '<Red>' },
  @{ Name = 'workbook-sql-dry-en'; Exit = 0; Status = 'DryRunOK'; Forbidden = '<Red>' },
  @{ Name = 'workbook-sql-default-pt'; Exit = 0; Status = 'OK'; Forbidden = '<Red>' },
  @{ Name = 'workbook-sql-default-en'; Exit = 0; Status = 'OK'; Forbidden = '<Red>' }
)
$root = Join-Path ([IO.Path]::GetTempPath()) "arc-workbook-mocks-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $root | Out-Null
$failed = 0
try {
  foreach ($test in $cases) {
    $caseRoot = Join-Path $root $test.Name
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-File', $PSCommandPath, '-Worker', '-Case', $test.Name, '-TestRoot', $caseRoot)) {
      $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::Start($start)
    try {
      $stdout = $process.StandardOutput.ReadToEndAsync()
      $stderr = $process.StandardError.ReadToEndAsync()
      $process.WaitForExit()
      $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
      $csv = @(Get-ChildItem -LiteralPath $caseRoot -Filter 'results_*.csv')
      $rows = if ($csv.Count) { @(Import-Csv -LiteralPath $csv[0].FullName -Encoding utf8) } else { @() }
      $problems = @()
      if ($process.ExitCode -ne $test.Exit) { $problems += "exit=$($process.ExitCode), expected=$($test.Exit)" }
      if ($test.Status -and -not @($rows | Where-Object Status -eq $test.Status).Count) { $problems += "missing $($test.Status) record" }
      if ($test.Rows -and -not @($rows | Where-Object { [int]$_.Rows -eq $test.Rows }).Count) { $problems += "missing row count $($test.Rows)" }
      if ($test.QueryCount -and $rows.Count -ne $test.QueryCount) { $problems += "queries=$($rows.Count), expected=$($test.QueryCount)" }
      if ($test.CacheHits -and @($rows | Where-Object CacheHit -eq 'True').Count -ne $test.CacheHits) { $problems += 'incorrect cache hit count' }
      if ($test.Observed -and $output -notmatch "(?m)^OBSERVED=$([regex]::Escape($test.Observed))\r?$") {
        $actual = [regex]::Match($output, '(?m)^OBSERVED=.*').Value.Trim()
        $problems += "expected OBSERVED=$($test.Observed); actual $actual"
      }
      if ($test.Forbidden -and $output.Contains($test.Forbidden)) { $problems += "unexpected output: $($test.Forbidden)" }
      if ($test.Required -and -not $output.Contains($test.Required)) { $problems += "missing output: $($test.Required)" }
      if ($test.RequiredCount -and [regex]::Matches($output, [regex]::Escape($test.Required)).Count -ne $test.RequiredCount) {
        $problems += "expected $($test.RequiredCount) selected parameter requests"
      }
      if ($test.Skipped) {
        $skipped = @($rows | Where-Object { $_.Kind -eq 'Parameter' -and $_.Status -eq 'Skipped (aguarda seleção)' })
        if ($skipped.Count -ne $test.Skipped) { $problems += "skipped=$($skipped.Count), expected=$($test.Skipped)" }
        if (-not $output.Contains('--- Awaiting row selection /')) { $problems += 'row-selection summary missing' }
      }
      if ($test.Exit -eq 0 -and @($rows | Where-Object { $_.Status -in 'FAILED', 'UnresolvedTokens', 'INCOMPLETE' }).Count) {
        $problems += 'success case contains failures'
      }
      if ($test.Parameter) {
        $records = @($rows | Where-Object { $_.Kind -eq 'Parameter' -and $_.Item -eq $test.Parameter -and $_.Status -eq 'FAILED' })
        if (-not $records.Count) { $problems += 'parameter failure missing from CSV' }
        if ($test.Scenario -and -not @($records | Where-Object Scenario -eq $test.Scenario).Count) { $problems += 'drill failure missing' }
        if ($output -notmatch "(?s)<Red>[^<]*$([regex]::Escape($test.Parameter))[^<]*</Red>") {
          $problems += 'parameter failure missing from red summary'
        }
      }
      if ($problems.Count) {
        $failed++
        Write-Host "FAIL $($test.Name): $($problems -join '; ')" -ForegroundColor Red
      } else { Write-Host "PASS $($test.Name)" -ForegroundColor Green }
      if ($test.Name -like 'workbook-*') {
        $summary = ($rows | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join '; '
        Write-Host "  exit=$($process.ExitCode); $summary"
      }
    } finally { $process.Dispose() }
  }
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force
}
Write-Host "$($cases.Count - $failed)/$($cases.Count) mock tests passed."
if ($failed) { exit 1 }
function Get-WorkbookItems($Items) {
  foreach ($item in $Items) {
    $item
    if ($item.type -eq 12) { Get-WorkbookItems $item.content.items }
  }
}
foreach ($project in 'arc-agent-support','arc-sql-payg-readiness','arc-sql-resource-reconciliation') {
  $path = Join-Path $PSScriptRoot "..\workbooks\$project-workbook.json"
  $templatePath = Join-Path $PSScriptRoot "..\templates\$project-azuredeploy.json"
  $raw = [IO.File]::ReadAllText($path)
  $workbook = $raw | ConvertFrom-Json -Depth 100
  $template = Get-Content -LiteralPath $templatePath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
  $embedded = $template.resources[0].properties.serializedData | ConvertFrom-Json -Depth 100
  if (($embedded | ConvertTo-Json -Depth 100 -Compress) -cne ($workbook | ConvertTo-Json -Depth 100 -Compress)) {
    throw "Embedded workbook mismatch: $project"
  }
  foreach ($file in $path,$templatePath) {
    $bytes = [IO.File]::ReadAllBytes($file)
    if ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { throw "Unexpected UTF-8 BOM: $file" }
  }
  $items = @(Get-WorkbookItems $workbook.items)
  $parameters = @($items | Where-Object type -eq 9 | ForEach-Object { $_.content.parameters })
  $names = @($parameters.name) + @($items | Where-Object type -eq 3 | ForEach-Object {
    $_.content.exportedParameters.parameterName; $_.content.exportParameterName
  })
  foreach ($match in [regex]::Matches($raw, '\{([A-Za-z][A-Za-z0-9_]*)\}')) {
    if ($match.Groups[1].Value -notin $names) { throw "Undefined parameter in ${project}: $($match.Value)" }
  }
  $tabs = @($workbook.items | Where-Object type -eq 12 | ForEach-Object { $_.conditionalVisibility } |
    Where-Object parameterName -eq 'SelectedTab' | ForEach-Object value)
  foreach ($link in $items | Where-Object type -eq 11 | ForEach-Object { $_.content.links }) {
    if ($link.linkTarget -eq 'parameter' -and $link.cellValue -eq 'SelectedTab' -and $link.subTarget -notin $tabs) {
      throw "Broken tab target in ${project}: $($link.subTarget)"
    }
  }
  $version = $template.contentVersion -replace '\.0$',''
  $projectDir = Join-Path $PSScriptRoot "..\workbooks\$project"
  foreach ($readme in 'README.md','README.pt-BR.md') {
    $head = (Get-Content -LiteralPath (Join-Path $projectDir $readme) -Encoding utf8 -TotalCount 12) -join "`n"
    $m = [regex]::Match($head, '\*\*(?:Current version|Version|Vers\u00e3o atual|Vers\u00e3o):?\*{0,2}\s*(\d+\.\d+\.\d+)')
    if (-not $m.Success -or $m.Groups[1].Value -ne $version) { throw "Version mismatch in ${project}/${readme}: expected $version" }
  }
  $changelogHead = (Get-Content -LiteralPath (Join-Path $projectDir 'CHANGELOG.md') -Encoding utf8 -TotalCount 8) -join "`n"
  if ($changelogHead -notmatch "(?m)^(\|v|## )$([regex]::Escape($version))\b") { throw "CHANGELOG.md top entry is not $version in $project" }
  $versionRow = "(?m)^\|[^\r\n]{0,40}\bv?$([regex]::Escape($version))\b"
  if (-not ($items | Where-Object { $_.type -eq 1 -and $_.content.json -match $versionRow })) {
    throw "In-workbook changelog has no row for $version in $project"
  }
  function Get-QueryCount($Group) {
    $count = 0
    foreach ($item in $Group) {
      if ($item.type -eq 3 -and $item.content.query) { $count++ }
      elseif ($item.type -eq 12) { $count += Get-QueryCount $item.content.items }
    }
    $count
  }
  foreach ($group in $workbook.items | Where-Object { $_.type -eq 12 -and $_.conditionalVisibility.parameterName -eq 'SelectedTab' }) {
    $queryCount = Get-QueryCount $group.content.items
    if ($queryCount -gt 10) { throw "Tab '$($group.conditionalVisibility.value)' in $project has $queryCount queries (limit 10, Resource Graph throttling)." }
  }
  foreach ($query in $items | Where-Object { $_.type -eq 3 -and $_.content.query }) {
    $length = $query.content.query.Length
    if ($length -gt 15000) { throw "Query '$($query.name)' in $project has $length characters (failed in the portal at 15-17k)." }
    if ($length -gt 12000) { Write-Host "WARN query over ~12,000 characters in ${project}: $($query.name) ($length)" }
  }
  if ($project -eq 'arc-agent-support') {
    $catalog = ($parameters | Where-Object name -eq 'ExtAvailable').query | ConvertFrom-Json -Depth 50
    $catalogJson = ($parameters | Where-Object name -eq 'ExtAvailableJson').query | ConvertFrom-Json -Depth 50
    if ($catalog.transformers[0].settings.tablePath -ne '$[*]' -or
        $catalogJson.transformers[0].settings.columns[0].path -ne '$[*].properties.version') {
      throw 'Extension GETARRAY transformers must read the root array.'
    }
    $detailQuery = ($items | Where-Object name -eq 'ext-detail').content.query
    if ($detailQuery -notmatch "case\(availCount == 0, 'Unknown" -or $detailQuery.Contains('Auto-upgrade will move it')) {
      throw 'Extension upgrade outlook must preserve catalog uncertainty and avoid upgrade guarantees.'
    }
    if (@($parameters | Where-Object name -match '^Released(Windows|Linux)[234]$').Count) { throw 'Unstable agent list samples returned.' }
    foreach ($name in 'ReleasedWindows','ReleasedLinux') {
      $arm = ($parameters | Where-Object name -eq $name).query | ConvertFrom-Json -Depth 50
      if ($arm.method -ne 'GET' -or $arm.path -notlike '*/agentVersions/latest') { throw "Expected exact latest endpoint: $name" }
    }
    foreach ($name in 'ext-detail','ext-available') {
      $query = ($items | Where-Object name -eq $name).content.query
      if (-not $query.Contains("location =~ '{ExtLocation}'")) { throw "Missing regional filter: $name" }
    }
    if (-not ($items | Where-Object name -eq 'extensions').content.query.Contains('by Publisher, ExtensionType, location')) {
      throw 'Extension grouping lost its region.'
    }
  } elseif ($project -eq 'arc-sql-payg-readiness') {
    $estimators = @($items | Where-Object { $_.type -eq 3 -and $_.content.query.Contains('| extend CoreEstimate = case(') })
    if ($estimators.Count -ne 7) { throw 'Unexpected SQL estimator count.' }
    foreach ($item in $estimators) {
      if (-not $item.content.query.Contains("iff(SqlVersionMajor == 'SQL Server 2025', 32, 24)") -or
          -not $item.content.query.Contains('min_of(RawCores, StandardCoreLimit)') -or
          -not $item.content.query.Contains("TopEdition == 'Not identified' or isnull(RawCores)")) {
        throw "SQL capacity regression: $($item.name)"
      }
    }
    $architectureQuery = ($items | Where-Object name -eq 'architecture_options').content.query
    if ($architectureQuery -match 'Standard m[aá]x\.? 24' -or
        -not $architectureQuery.Contains('not a billing cap') -or
        -not $architectureQuery.Contains('teto de cobran')) {
      throw 'Architecture recommendations must not describe Standard capacity as a billing cap.'
    }
  } else {
    $queries = @($items | Where-Object type -eq 3)
    if ($queries.Count -ne 15) { throw 'Expected fifteen reconciliation exception queries.' }
    $allQueryText = ($queries | ForEach-Object { $_.content.query }) -join "`n"
    if (-not $allQueryText.Contains('LinuxAgent.SqlServer') -or
        -not $allQueryText.Contains('Parent instance container absent from ARG') -or
        -not $allQueryText.Contains('Declared FCI host has no node projection') -or
        -not $allQueryText.Contains('SQL extension absent on the host machine') -or
        $allQueryText.Contains('{StaleDays}') -or
        ($parameters | Where-Object name -eq 'StaleDays')) {
      throw 'Reconciliation orphan and Linux extension coverage regressed, or the removed stale-inventory check returned.'
    }
    foreach ($query in $queries) {
      if ($query.content.queryType -ne 1 -or $query.content.gridSettings.rowLimit -ne 1000) {
        throw 'Reconciliation must use read-only ARG queries and explicit grid limits.'
      }
    }
    $fci = $queries | Where-Object { $_.content.query.Contains('consolidatedProjectionCount') }
    $ag = $queries | Where-Object { $_.content.query.Contains('hasUnhealthy=') }
    $license = $queries | Where-Object { $_.content.query.Contains("validationType='Licensing / billing review'") }
    if (-not $fci.content.query.Contains("| where severity != 'Info'") -or
        -not $ag.content.query.Contains("| where severity != 'Info'") -or
        -not $ag.content.query.Contains('by correlationKey,availabilityGroupId,subscriptionId') -or
        -not $ag.content.query.Contains('missingHealth=countif(isempty(synchronizationHealth))') -or
        -not $license.content.query.Contains('| where isnotempty(finding)')) {
      throw 'Reconciliation exception-only filters or unknown-metadata preservation regressed.'
    }
  }
  Write-Host "PASS workbook invariants: $project"
}
exit 0
