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
    if ($Query -like 'fail-*') { [Console]::WriteLine("FAILED_PARAMETER_QUERY=$Query"); throw "Mock error: $Query" }
    if ($Query -like 'derive:*') {
      [pscustomobject]@{ value = $Query.Substring(7) }
      if ($Case -eq 'override-dependent') { [pscustomobject]@{ value = 'second row' } }
    } elseif ($Query -like 'observe:*') {
      [Console]::WriteLine("OBSERVED=$($Query.Substring(8))")
      [pscustomobject]@{ value = $Query.Substring(8) }
    } elseif ($Query -eq 'extensions') {
      [pscustomobject]@{ Publisher = 'MockPublisher'; ExtensionType = 'MockType'; Location = 'MockLocation' }
    } elseif ($Case -like 'workbook-*') {
      [pscustomobject]@{ value = '1.69' }
    } elseif ($Query -ne 'empty') {
      [pscustomobject]@{ value = 'ok' }
    }
  }
  function Invoke-AzRestMethod {
    param($Method, $Path, $ErrorAction)
    [Console]::WriteLine("ARM_PATH=$Path")
    if ($Case -eq 'selection-drill-failure' -and $Path -like '/selected/*') { throw 'Mock selected extension failure' }
    if ($Path -like '/fail-*') { throw "Mock error: $Path" }
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
    'failed-query' { $items = @(New-Query 'fail-query') }
    'unresolved-dry' { $items = @(New-Query '{Missing}'); $arguments.DryRun = $true }
    'unresolved-live' { $items = @(New-Query '{Missing}') }
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
  @{ Name = 'failed-query'; Exit = 1; Status = 'FAILED' },
  @{ Name = 'unresolved-dry'; Exit = 1; Status = 'UnresolvedTokens' },
  @{ Name = 'unresolved-live'; Exit = 1; Status = 'UnresolvedTokens' },
  @{ Name = 'unresolved-burst'; Exit = 1; Status = 'UnresolvedTokens' },
  @{ Name = 'override-dependent'; Exit = 0; Observed = '1.70' },
  @{ Name = 'scalar-arg'; Exit = 0; Observed = '1.69' },
  @{ Name = 'scalar-arm'; Exit = 0; Observed = '1.69' },
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
  @{ Name = 'workbook-agent-default-pt'; Exit = 0; Status = 'OK'; Skipped = 2; Forbidden = '<Red>' },
  @{ Name = 'workbook-agent-default-en'; Exit = 0; Status = 'OK'; Skipped = 2; Forbidden = '<Red>' },
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
      if ($test.Exit -eq 0 -and @($rows | Where-Object { $_.Status -in 'FAILED', 'UnresolvedTokens' }).Count) {
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
exit 0
