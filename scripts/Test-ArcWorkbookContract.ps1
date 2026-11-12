#Requires -Version 7.0
<#
.SYNOPSIS
  Contract check: compares what the workbook queries use against Microsoft public metadata.
  Verificacao de contrato: compara o que as queries usam com os metadados publicos da Microsoft.

.DESCRIPTION
  Layer 1 - Resource contract (offline of your tenant; needs internet)
    Every properties.* path used in an ARG query must exist in the public ARM REST API specs
    (Azure/azure-rest-api-specs) of the resource type the query reads:
      Microsoft.HybridCompute  (machines, machines/extensions)
      Microsoft.AzureArcData   (sqlServerInstances, databases, availabilityGroups, sqlServerLicenses, sqlServerEsuLicenses)
    Free-form objects (for example extension settings) are reported as FREEFORM, not as errors.
    String literals compared with a property are checked against the spec enum (heuristic, WARN only).
  Layer 2 - Azure Resource Graph contract
    The ARG table and every resource type literal must be listed in the Learn page "Resource Graph supported tables and resource types"
    (MicrosoftDocs/azure-docs, supported-tables-resources.md).
  Layer 3 - ARM calls
    Paths of ARM-backed queries (queryType 12) must exist as GET operations in the spec of the api-version the workbook uses.
  Live (optional, -Live; read-only ARG)
    Counts how many resources of your tenant populate each property and compares the distinct values with the spec enum.

  What this proves: that the workbook reads documented properties of documented resources and tables.
  What it does not prove: that heuristics (supported, on track, needs action) match Microsoft policy.

  Exit code 1 when a path, type, table or ARM operation is not found in the metadata (FAIL). WARN/UNVERIFIED do not fail.
  Facts verified against the sources above at run time; the report prints the spec versions and the run date.

.EXAMPLE
  ./Test-ArcWorkbookContract.ps1
  ./Test-ArcWorkbookContract.ps1 -WorkbookPath ./workbooks/arc-sql-payg-readiness-workbook.json -Live -ReportPath ./contract-report.md
#>
[CmdletBinding()]
param(
  [string[]]$WorkbookPath,
  [string]$HybridComputeVersion = '2026-09-01',
  [string[]]$ArcDataVersions = @('2026-01-01', '2026-03-01-preview'),
  [string]$SqlVirtualMachineVersion = '2023-10-01',
  [string]$CacheDir = (Join-Path ([IO.Path]::GetTempPath()) 'arc-contract-cache'),
  [switch]$Live,
  [string[]]$Subscriptions,
  [string]$ReportPath
)

$ErrorActionPreference = 'Stop'

$script:SpecRoot = @{
  hybridcompute = 'specification/hybridcompute/resource-manager/Microsoft.HybridCompute/HybridCompute'
  azurearcdata  = 'specification/azurearcdata/resource-manager/Microsoft.AzureArcData/AzureArcData'
  sqlvirtualmachine = 'specification/sqlvirtualmachine/resource-manager/Microsoft.SqlVirtualMachine/SqlVirtualMachine'
}
$script:ArgDocUrl = 'https://raw.githubusercontent.com/MicrosoftDocs/azure-docs/main/articles/governance/resource-graph/reference/supported-tables-resources.md'

$script:DefensiveLiterals = @(
  'properties.sqlImageSku=Unknown'
  'properties.sqlServerLicenseType=NotSet'
  'properties.activationState=Active'
)

# Properties outside the compared REST specs whose existence is documented by Microsoft (verified 2026-11-12). Reported as DOCUMENTED, never as OK.
$script:DocumentedSources = @(
  @{ Type = 'microsoft.advisor/'; Source = 'Learn Resource Graph samples (Advisor, FinOps) and Advisor REST spec 2025-01-01'
     Paths = @('properties.category', 'properties.impact', 'properties.impactedField', 'properties.lastUpdated', 'properties.recommendationTypeId', 'properties.resourceMetadata.resourceId', 'properties.shortDescription.problem', 'properties.shortDescription.solution') }
  @{ Type = 'microsoft.policyinsights/'; Source = 'Learn Resource Graph samples (Policy)'
     Paths = @('properties.complianceState', 'properties.policyAssignmentName', 'properties.policyDefinitionId', 'properties.policyDefinitionReferenceId', 'properties.resourceId', 'properties.resourceType') }
  @{ Type = 'microsoft.resources/subscriptions'; Source = 'Subscriptions REST spec 2022-12-01 (SubscriptionPolicies.quotaId)'
     Paths = @('properties.subscriptionPolicies.quotaId') }
  @{ Type = 'microsoft.compute/virtualmachines'; Source = 'Azure Policy alias Microsoft.Compute/virtualMachines/hardwareProfile.vmSize (Get-AzPolicyAlias, 2026-11-12)'
     Paths = @('properties.hardwareProfile.vmSize') }
  @{ Type = 'resourcechanges'; Source = 'Learn "Get resource changes" (Resource Graph change history)'
     Paths = @('properties.targetResourceId', 'properties.targetResourceType', 'properties.changeType', 'properties.changes', 'properties.changeAttributes.changedBy', 'properties.changeAttributes.clientType', 'properties.changeAttributes.timestamp') }
)

# Free-form extension settings: no REST spec. Observations come from read-only ARG counts (2026-11-12, 1310 SQL extensions in 2 scopes) and a third-party public script; they never become OK.
$script:ObservedNotes = @{
  'properties.settings.LicenseType'                          = 'free-form setting; observed in 1081 of 1310 SQL extensions (values Paid or absent); the third-party script lists Paid, PAYG, LicenseOnly'
  'properties.settings.UsePhysicalCoreLicense.IsApplied'     = 'free-form setting; observed in 2 of 1310 SQL extensions as {IsApplied:false, LastUpdatedTimestamp}'
  'properties.settings.enableExtendedSecurityUpdates'        = 'free-form setting; 0 of 1310 SQL extensions populate it; path read by a third-party public script, not by a Microsoft source'
  'properties.settings.ConsentToRecurringPAYG.Consented'     = 'free-form setting; 0 of 1310 SQL extensions populate it; path read and written by a third-party public script, not by a Microsoft source'
}

$script:ObservedLiteralNotes = @{
  'properties.sqlImageSku=Unknown'          = 'not observed in 18 SQL virtual machines in 2 scopes (2026-11-12; values seen: Developer, Enterprise)'
  'properties.sqlServerLicenseType=NotSet'  = 'not observed in 18 SQL virtual machines in 2 scopes (2026-11-12; values seen: PAYG, AHUB)'
  'properties.activationState=Active'       = 'not observed; the only license seen in 2 scopes was Deactivated (2026-11-12); the spec value is Activated'
}

function Get-SourceNote {
  param([string]$PathText, [string[]]$Types)
  foreach ($e in $script:DocumentedSources) {
    if (@($Types | Where-Object { $_ -like "$($e.Type)*" }) -and $e.Paths -contains $PathText) { return $e.Source }
  }
}

# ARG type -> (service, resource definition name in the spec)
$script:TypeMap = @{
  'microsoft.hybridcompute/machines'                          = @('hybridcompute', 'Machine')
  'microsoft.hybridcompute/machines/extensions'               = @('hybridcompute', 'MachineExtension')
  'microsoft.azurearcdata/sqlserverinstances'                 = @('azurearcdata', 'SqlServerInstance')
  'microsoft.azurearcdata/sqlserverinstances/databases'       = @('azurearcdata', 'SqlServerDatabaseResource')
  'microsoft.azurearcdata/sqlserverinstances/availabilitygroups' = @('azurearcdata', 'SqlServerAvailabilityGroupResource')
  'microsoft.azurearcdata/sqlserverlicenses'                  = @('azurearcdata', 'SqlServerLicense')
  'microsoft.azurearcdata/sqlserveresulicenses'               = @('azurearcdata', 'SqlServerEsuLicense')
  'microsoft.sqlvirtualmachine/sqlvirtualmachines'            = @('sqlvirtualmachine', 'SqlVirtualMachine')
}

# ---------- download with cache ----------
function Get-HttpText {
  param([string]$Url)
  New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
  $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Url)))
  $file = Join-Path $CacheDir "$sha.txt"
  if (Test-Path $file) { return Get-Content -Raw -Encoding utf8 $file }
  $headers = @{ 'User-Agent' = 'AzureArcBRTips-contract-check' }
  if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $env:GITHUB_TOKEN" }
  $text = (Invoke-WebRequest -Uri $Url -Headers $headers -UseBasicParsing).Content
  if ($text -is [byte[]]) { $text = [Text.Encoding]::UTF8.GetString($text) }
  [IO.File]::WriteAllText($file, $text, [Text.UTF8Encoding]::new($false))
  $text
}

$script:SpecCache = @{}
function Get-SpecSet {
  param([string]$Service, [string]$Version)
  $key = "$Service|$Version"
  if ($script:SpecCache.ContainsKey($key)) { return $script:SpecCache[$key] }
  $result = $null
  foreach ($track in 'stable', 'preview') {
    $dir = "$($script:SpecRoot[$Service])/$track/$Version"
    try { $listing = Get-HttpText "https://api.github.com/repos/Azure/azure-rest-api-specs/contents/$dir" | ConvertFrom-Json } catch { continue }
    $files = [Collections.Hashtable]::new()
    foreach ($entry in @($listing | Where-Object { $_.type -eq 'file' -and $_.name -like '*.json' })) {
      $files[$entry.name] = Get-HttpText $entry.download_url | ConvertFrom-Json -AsHashtable -Depth 100
    }
    if ($files.Count) { $result = [pscustomobject]@{ Service = $Service; Version = $Version; Track = $track; Files = $files }; break }
  }
  $script:SpecCache[$key] = $result
  $result
}

# ---------- schema walking ----------
function Resolve-SpecRef {
  param([string]$Ref, [string]$File, $Spec)
  $filePart, $pointer = $Ref -split '#', 2
  $target = $File
  if ($filePart) {
    $leaf = ($filePart -split '[\\/]')[-1]
    if (-not $Spec.Files.ContainsKey($leaf)) { return $null }
    $target = $leaf
  }
  $node = $Spec.Files[$target]
  foreach ($seg in ($pointer.TrimStart('/') -split '/')) {
    if ($seg -eq '') { continue }
    $seg = $seg.Replace('~1', '/').Replace('~0', '~')
    if ($node -isnot [System.Collections.IDictionary] -or -not $node.Contains($seg)) { return $null }
    $node = $node[$seg]
  }
  @{ Schema = $node; File = $target }
}

function Expand-Schema {
  param($Schema, [string]$File, $Spec, [int]$Depth = 0)
  $out = [pscustomobject]@{ Props = [Collections.Hashtable]::new(); Free = $false; Unknown = $false; Schema = $Schema; File = $File }
  if ($Depth -gt 14 -or $null -eq $Schema) { $out.Unknown = $true; return $out }
  if ($Schema.Contains('$ref')) {
    $r = Resolve-SpecRef -Ref $Schema['$ref'] -File $File -Spec $Spec
    if (-not $r) { $out.Unknown = $true; return $out }
    return Expand-Schema -Schema $r.Schema -File $r.File -Spec $Spec -Depth ($Depth + 1)
  }
  if ($Schema['type'] -eq 'array' -and $Schema.Contains('items')) {
    return Expand-Schema -Schema $Schema['items'] -File $File -Spec $Spec -Depth ($Depth + 1)
  }
  foreach ($part in @($Schema['allOf'])) {
    if (-not $part) { continue }
    $e = Expand-Schema -Schema $part -File $File -Spec $Spec -Depth ($Depth + 1)
    foreach ($k in $e.Props.Keys) { $out.Props[$k] = $e.Props[$k] }
    if ($e.Free) { $out.Free = $true }
    if ($e.Unknown) { $out.Unknown = $true }
  }
  if ($Schema.Contains('properties')) {
    foreach ($k in $Schema['properties'].Keys) { $out.Props[$k] = @{ Schema = $Schema['properties'][$k]; File = $File } }
  }
  if ($Schema.Contains('additionalProperties') -and $Schema['additionalProperties']) { $out.Free = $true }
  $isObject = (-not $Schema.Contains('type')) -or $Schema['type'] -eq 'object'
  if ($isObject -and -not $Schema.Contains('properties') -and -not $Schema.Contains('allOf')) { $out.Free = $true }
  if ($Schema.Contains('enum') -or $Schema.Contains('x-ms-enum')) { $out.Free = $false }
  $out
}

function Find-SchemaPath {
  # Status: Found | CaseOnly | Freeform | Unknown | Missing
  param($Root, [string]$File, $Spec, [string[]]$Segments)
  $cur = Expand-Schema -Schema $Root -File $File -Spec $Spec
  $status = 'Found'
  foreach ($seg in $Segments) {
    $next = $null
    if ($cur.Props.ContainsKey($seg)) { $next = $cur.Props[$seg] }
    else {
      $ci = @($cur.Props.Keys | Where-Object { $_ -ieq $seg })
      if ($ci.Count -ge 1) { $next = $cur.Props[$ci[0]]; $status = 'CaseOnly' }
    }
    if ($null -eq $next) {
      if ($cur.Free) { return [pscustomobject]@{ Status = 'Freeform'; Leaf = $null } }
      if ($cur.Unknown) { return [pscustomobject]@{ Status = 'Unknown'; Leaf = $null } }
      return [pscustomobject]@{ Status = 'Missing'; Leaf = $null }
    }
    $cur = Expand-Schema -Schema $next.Schema -File $next.File -Spec $Spec
  }
  [pscustomobject]@{ Status = $status; Leaf = $cur }
}

function Get-EnumValues {
  param($Leaf)
  if ($Leaf -and $Leaf.Schema -and $Leaf.Schema.Contains('enum')) { return @($Leaf.Schema['enum'] | ForEach-Object { [string]$_ }) }
  @()
}

function Find-Definition {
  param($Spec, [string]$Name)
  foreach ($f in $Spec.Files.Keys) {
    $d = $Spec.Files[$f]['definitions']
    if ($d -and $d.Contains($Name)) { return @{ Schema = $d[$Name]; File = $f } }
  }
  $null
}

# ---------- workbook parsing ----------
function Get-WorkbookQueries {
  param([string]$Path)
  $wb = Get-Content -Raw -Encoding utf8 $Path | ConvertFrom-Json -AsHashtable -Depth 100
  $queries = [Collections.Generic.List[object]]::new()
  $params = [Collections.Generic.List[object]]::new()
  $walk = $null
  $walk = {
    param($node, $name)
    if ($node -is [System.Collections.IDictionary]) {
      if ($node.Contains('name') -and $node['name'] -is [string]) { $name = $node['name'] }
      if ($node.Contains('query') -and $node['query'] -is [string]) { $queries.Add([pscustomobject]@{ Name = $name; Query = $node['query'] }) }
      if ($node.Contains('name') -and $node.Contains('type') -and $node['name'] -is [string] -and ($node.Contains('value') -or $node.Contains('query'))) {
        $params.Add([pscustomobject]@{ Name = $node['name']; Value = [string]$node['value'] })
      }
      foreach ($v in @($node.Values)) { & $walk $v $name }
    } elseif ($node -is [System.Collections.IEnumerable] -and $node -isnot [string]) {
      foreach ($v in $node) { & $walk $v $name }
    }
  }
  & $walk $wb ''
  [pscustomobject]@{ Queries = $queries; Params = $params }
}

function Expand-QueryPropertyAliases {
  param([string]$Query)
  $aliases = @([regex]::Matches($Query, "(?<![\w.])([A-Za-z_]\w*)\s*=\s*properties\b(?![.\[])") |
    ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
  foreach ($alias in $aliases) {
    $Query = [regex]::Replace($Query, "(?<![\w.])$([regex]::Escape($alias))(?=\.|\[')", 'properties')
  }
  $Query
}

function Get-QueryPropertyPaths {
  param([string]$Query)
  $Query = Expand-QueryPropertyAliases $Query
  $paths = [Collections.Generic.List[object]]::new()
  foreach ($m in [regex]::Matches($Query, "(?<![\w])properties((?:\.[A-Za-z_]\w*|\['[^']+'\])+)")) {
    $segs = @('properties') + @([regex]::Matches($m.Groups[1].Value, "\.([A-Za-z_]\w*)|\['([^']+)'\]") | ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } })
    $paths.Add([pscustomobject]@{ Text = ($segs -join '.'); Segments = $segs })
  }
  $paths
}

function Get-QueryTypes {
  param([string]$Query)
  @([regex]::Matches($Query, "'(microsoft\.[a-z0-9\.]+/[a-z0-9/]+)'", 'IgnoreCase') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Select-Object -Unique)
}

function Get-QueryEnumChecks {
  # Heuristic: literals compared directly with a property (or with an alias assigned from it).
  param([string]$Query)
  $Query = Expand-QueryPropertyAliases $Query
  $checks = [Collections.Generic.List[object]]::new()
  $keys = @{}
  foreach ($m in [regex]::Matches($Query, "(?<![\w])properties(?:\.[A-Za-z_]\w*)+")) { $keys[$m.Value] = $m.Value }
  foreach ($m in [regex]::Matches($Query, "([A-Za-z_]\w*)\s*=\s*(?:tostring|tolower|toupper)?\(?\s*(properties(?:\.[A-Za-z_]\w*)+)")) {
    if (-not $keys.ContainsKey($m.Groups[1].Value)) { $keys[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  foreach ($k in $keys.Keys) {
    $pat = "(?<![\w\.])(?:tostring\(|tolower\()?$([regex]::Escape($k))\)?\s*(?:==|=~|!=|!~|in~|in)\s*(\([^)]*\)|'[^']*')"
    foreach ($m in [regex]::Matches($Query, $pat)) {
      foreach ($lit in [regex]::Matches($m.Groups[1].Value, "'([^']*)'")) {
        $checks.Add([pscustomobject]@{ Path = $keys[$k]; Literal = $lit.Groups[1].Value })
      }
    }
  }
  $checks
}

function Get-ArgTableMap {
  $tables = @{}
  $current = $null
  foreach ($line in ((Get-HttpText $script:ArgDocUrl) -split "`r?`n")) {
    if ($line -match '^##\s+([a-z0-9]+)\s*$') { $current = $Matches[1].ToLowerInvariant(); $tables[$current] = [Collections.Generic.HashSet[string]]::new(); continue }
    if ($current -and $line -match '^-\s+(microsoft\.[^\s]+)') { [void]$tables[$current].Add($Matches[1].ToLowerInvariant()) }
  }
  $tables
}

function Get-QueryTable {
  param([string]$Query)
  $lines = @($Query -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('//') })
  if ($lines -and $lines[0] -match '^([A-Za-z]+)\b') { return $Matches[1].ToLowerInvariant() }
  $null
}

function Test-ArmPathInSpec {
  param([string]$ArmPath, $Spec)
  $armLeaf = ($ArmPath -replace '\?.*$', '').TrimEnd('/')
  foreach ($f in $Spec.Files.Keys) {
    $paths = $Spec.Files[$f]['paths']
    if (-not $paths) { continue }
    foreach ($p in $paths.Keys) {
      $rx = '^' + ([regex]::Escape($p) -replace '\\\{[^}]+\}', '[^/]+') + '$'
      if ($armLeaf -match $rx -and $paths[$p].Contains('get')) { return $p }
    }
  }
  $null
}

function Get-AllSpecs {
  $specs = @{}
  $hc = Get-SpecSet -Service hybridcompute -Version $HybridComputeVersion
  if (-not $hc) { throw "HybridCompute spec $HybridComputeVersion not found." }
  $specs['hybridcompute'] = @($hc)
  $specs['azurearcdata'] = @($ArcDataVersions | ForEach-Object { Get-SpecSet -Service azurearcdata -Version $_ } | Where-Object { $_ })
  if (-not $specs['azurearcdata']) { throw 'No Arc data spec found.' }
  $sqlvm = Get-SpecSet -Service sqlvirtualmachine -Version $SqlVirtualMachineVersion
  $specs['sqlvirtualmachine'] = @(@($sqlvm) | Where-Object { $_ })
  $specs
}

function Test-TypePath {
  param([string]$Type, [string[]]$Segments, $Specs)
  $svc, $defName = $script:TypeMap[$Type]
  foreach ($spec in $Specs[$svc]) {
    $def = Find-Definition -Spec $spec -Name $defName
    if (-not $def) { continue }
    $r = Find-SchemaPath -Root $def.Schema -File $def.File -Spec $spec -Segments $Segments
    if ($r.Status -in 'Found', 'CaseOnly', 'Freeform') { return $r }
  }
  $null
}

function Invoke-ContractCheck {
  param([string[]]$Workbooks)
  $findings = [Collections.Generic.List[object]]::new()
  $add = { param($Layer, $Wb, $Item, $Status, $Detail) $findings.Add([pscustomobject]@{ Layer = $Layer; Workbook = $Wb; Item = $Item; Status = $Status; Detail = $Detail }) }

  $specs = Get-AllSpecs
  $argTables = Get-ArgTableMap

  foreach ($wbPath in $Workbooks) {
    $wbName = [IO.Path]::GetFileNameWithoutExtension($wbPath) -replace '-workbook$', ''
    $parsed = Get-WorkbookQueries -Path $wbPath

    foreach ($q in $parsed.Queries) {
      $text = $q.Query.Trim()
      if ($text.StartsWith('{')) {
        # Layer 3: ARM call
        try { $arm = $text | ConvertFrom-Json -AsHashtable -Depth 20 } catch { continue }
        if (-not $arm.Contains('path')) { continue }
        $path = [string]$arm['path']
        $verParam = @($arm['urlParams'] | Where-Object { $_.key -eq 'api-version' })[0]
        $ver = if ($verParam) { [string]$verParam.value } else { '' }
        if ($ver -match '^\{(\w+)\}$') { $pn = $Matches[1]; $ver = [string](@($parsed.Params | Where-Object { $_.Name -eq $pn })[0].Value) }
        if ($path -notmatch '(?i)/providers/Microsoft\.HybridCompute/') { & $add 'ARM' $wbName $q.Name 'UNVERIFIED' "service not covered: $path"; continue }
        $spec = Get-SpecSet -Service hybridcompute -Version $ver
        if (-not $spec) { & $add 'ARM' $wbName $q.Name 'FAIL' "api-version '$ver' not found in azure-rest-api-specs ($path)"; continue }
        $hit = Test-ArmPathInSpec -ArmPath $path -Spec $spec
        if ($hit) { & $add 'ARM' $wbName $q.Name 'OK' "GET $hit @ $ver ($($spec.Track))" }
        else { & $add 'ARM' $wbName $q.Name 'FAIL' "GET $path not in spec $ver" }
        continue
      }

      # ARG query
      $table = Get-QueryTable $text
      if (-not $table -or -not $argTables.ContainsKey($table)) {
        if ($table -and $text -match '^\s*[A-Za-z]+\s*(\||$)') { & $add 'ARG-table' $wbName $q.Name 'FAIL' "table '$table' is not in the Learn supported-tables list" }
        continue
      }
      $types = Get-QueryTypes $text
      if ($table -eq 'resourcechanges') {
        # Type literals are the changed (target) resource types, and properties.* is the change record, not the target resource schema.
        foreach ($t in $types) {
          $listed = @($argTables.Keys | Where-Object { $argTables[$_].Contains($t) })
          if ($listed) { & $add 'ARG-type' $wbName "$($q.Name): $t" 'OK' "target type, listed under: $($listed -join ', ')" }
          else { & $add 'ARG-type' $wbName "$($q.Name): $t" 'FAIL' 'target type is not listed under any Learn table' }
        }
        foreach ($pth in (Get-QueryPropertyPaths $text | Sort-Object Text -Unique)) {
          $src = Get-SourceNote -PathText $pth.Text -Types @('resourcechanges')
          if ($src) { & $add 'Property' $wbName "$($q.Name): $($pth.Text)" 'DOCUMENTED' $src }
          else {
            $obs = $script:ObservedNotes[$pth.Text]
            & $add 'Property' $wbName "$($q.Name): $($pth.Text)" 'UNVERIFIED' ("not in the REST specs or Learn change-record fields" + $(if ($obs) { "; $obs" } else { '' }))
          }
        }
        continue
      }
      $mentioned = @($argTables.Keys | Where-Object { $text -match "(?i)(?<![\w.])$_(?![\w.])" })
      foreach ($t in $types) {
        $listed = @($mentioned | Where-Object { $argTables[$_].Contains($t) })
        if ($listed) { & $add 'ARG-type' $wbName "$($q.Name): $t" 'OK' ($listed -join ', ') }
        else { & $add 'ARG-type' $wbName "$($q.Name): $t" 'FAIL' "not listed under: $($mentioned -join ', ')" }
      }

      $covered = @($types | Where-Object { $script:TypeMap.ContainsKey($_) })
      $uncovered = @($types | Where-Object { -not $script:TypeMap.ContainsKey($_) -and $_ -match 'microsoft\.(advisor|policyinsights|authorization|resources)/' })
      $other = @($types | Where-Object { -not $script:TypeMap.ContainsKey($_) -and $_ -notin $uncovered })
      foreach ($pth in (Get-QueryPropertyPaths $text | Sort-Object Text -Unique)) {
        $foundIn = [Collections.Generic.List[string]]::new(); $best = $null; $tracks = @()
        foreach ($t in $covered) {
          $svc, $defName = $script:TypeMap[$t]
          foreach ($spec in $specs[$svc]) {
            $def = Find-Definition -Spec $spec -Name $defName
            if (-not $def) { continue }
            $r = Find-SchemaPath -Root $def.Schema -File $def.File -Spec $spec -Segments $pth.Segments
            if ($r.Status -in 'Found', 'CaseOnly', 'Freeform') {
              $foundIn.Add("$t@$($spec.Version)"); $tracks += $spec.Track
              if (-not $best -or $r.Status -eq 'Found') { $best = $r }
            }
          }
        }
        if ($foundIn.Count) {
          $st = switch ($best.Status) { 'Found' { 'OK' } 'CaseOnly' { 'WARN' } 'Freeform' { 'FREEFORM' } }
          $note = if ($best.Status -eq 'CaseOnly') { 'case differs from spec; ' } else { '' }
          $onlyPreview = ($tracks | Select-Object -Unique) -eq 'preview'
          if ($onlyPreview) { $note += 'only in preview spec; ' }
          & $add 'Property' $wbName "$($q.Name): $($pth.Text)" $st ($note + (($foundIn | Select-Object -Unique) -join ', '))
        } elseif ($uncovered -or $other -or -not $covered) {
          $src = Get-SourceNote -PathText $pth.Text -Types $types
          if ($src) { & $add 'Property' $wbName "$($q.Name): $($pth.Text)" 'DOCUMENTED' $src }
          else {
            $obs = $script:ObservedNotes[$pth.Text]
            & $add 'Property' $wbName "$($q.Name): $($pth.Text)" 'UNVERIFIED' ("type(s) not covered by the specs: $((@($uncovered) + @($other)) -join ', ')" + $(if ($obs) { "; $obs" } else { '' }))
          }
        } else {
          & $add 'Property' $wbName "$($q.Name): $($pth.Text)" 'FAIL' "not found in spec for $($covered -join ', ')"
        }
      }

      foreach ($chk in (Get-QueryEnumChecks $text | Sort-Object Path, Literal -Unique)) {
        $segs = $chk.Path -split '\.'
        $enum = @()
        foreach ($t in $covered) {
          $svc, $defName = $script:TypeMap[$t]
          foreach ($spec in $specs[$svc]) {
            $def = Find-Definition -Spec $spec -Name $defName
            if (-not $def) { continue }
            $r = Find-SchemaPath -Root $def.Schema -File $def.File -Spec $spec -Segments $segs
            if ($r.Status -in 'Found', 'CaseOnly') { $enum += Get-EnumValues $r.Leaf }
          }
        }
        $enum = @($enum | Select-Object -Unique)
        if ($enum.Count -and $chk.Literal -notin $enum) {
          # Sentinels the workbook maps to "Not reported" or tolerates defensively; the spec does not list them, so they are never reported as OK.
          if ("$($chk.Path)=$($chk.Literal)" -in $script:DefensiveLiterals) {
            $lit = "$($chk.Path)=$($chk.Literal)"
            $obsLit = $script:ObservedLiteralNotes[$lit]
            & $add 'Value' $wbName "$($q.Name): $($chk.Path) = '$($chk.Literal)'" 'UNVERIFIED' ("defensive literal, not in spec enum: $($enum -join ', ')" + $(if ($obsLit) { "; $obsLit" } else { '' }))
          } else {
            & $add 'Value' $wbName "$($q.Name): $($chk.Path) = '$($chk.Literal)'" 'WARN' "not in spec enum (open enum or derived label): $($enum -join ', ')"
          }
        }
      }
    }
  }
  ,$findings
}

function Invoke-LiveCheck {
  param([string[]]$Workbooks, [string[]]$Subs)
  $out = [Collections.Generic.List[object]]::new()
  $specs = Get-AllSpecs
  $byType = @{}
  foreach ($wbPath in $Workbooks) {
    foreach ($q in (Get-WorkbookQueries -Path $wbPath).Queries) {
      if ($q.Query.Trim().StartsWith('{')) { continue }
      $types = Get-QueryTypes $q.Query | Where-Object { $script:TypeMap.ContainsKey($_) }
      $paths = Get-QueryPropertyPaths $q.Query
      foreach ($t in $types) {
        foreach ($p in $paths) {
          if (-not $byType.ContainsKey($t)) { $byType[$t] = @{} }
          if (-not $byType[$t].ContainsKey($p.Text) -and (Test-TypePath -Type $t -Segments $p.Segments -Specs $specs)) { $byType[$t][$p.Text] = $p.Segments }
        }
      }
    }
  }
  foreach ($t in $byType.Keys) {
    $segList = @($byType[$t].Keys | Sort-Object)
    if (-not $segList) { continue }
    $cols = for ($i = 0; $i -lt $segList.Count; $i++) { "c$i=countif(isnotnull($($segList[$i])))" }
    $query = "resources | where type =~ '$t' | summarize total=count(), $($cols -join ', ')"
    $request = @{ query = $query; options = @{ resultFormat = 'objectArray' } }
    if ($Subs) { $request.subscriptions = @($Subs) }
    $resp = Invoke-AzRestMethod -Method POST -Path '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Payload ($request | ConvertTo-Json -Depth 6)
    if ($resp.StatusCode -ne 200) {
      $detail = try { $e = ($resp.Content | ConvertFrom-Json).error; "$($e.code): $($e.message) $(@($e.details | ForEach-Object { $_.message }) -join ' | ')" } catch { "$($resp.Content)" }
      if ($detail.Length -gt 400) { $detail = $detail.Substring(0, 400) }
      $out.Add([pscustomobject]@{ Type = $t; Path = '*'; Total = 0; Populated = 0; Note = "HTTP $($resp.StatusCode) $detail" }); continue
    }
    $row = @(($resp.Content | ConvertFrom-Json -Depth 20).data)[0]
    for ($i = 0; $i -lt $segList.Count; $i++) {
      $n = [int]$row."c$i"
      $note = if ($row.total -gt 0 -and $n -eq 0) { 'never populated in this tenant' } else { '' }
      $out.Add([pscustomobject]@{ Type = $t; Path = $segList[$i]; Total = [int]$row.total; Populated = $n; Note = $note })
    }
    Start-Sleep -Milliseconds 500
  }
  $out
}

if ($MyInvocation.InvocationName -ne '.') {
  if (-not $WorkbookPath) { $WorkbookPath = @(Get-ChildItem (Join-Path $PSScriptRoot '..\workbooks') -Filter '*-workbook.json' | ForEach-Object FullName) }
  $findings = Invoke-ContractCheck -Workbooks $WorkbookPath
  $summary = $findings | Group-Object Layer, Status | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Layer_Status = $_.Name; Count = $_.Count } }
  $summary | Format-Table -AutoSize | Out-String | Write-Host
  $bad = @($findings | Where-Object { $_.Status -in 'FAIL', 'WARN', 'UNVERIFIED' })
  foreach ($b in $bad) { Write-Host ("{0,-10} {1,-10} {2,-28} {3} | {4}" -f $b.Status, $b.Layer, $b.Workbook, $b.Item, $b.Detail) -ForegroundColor $(if ($b.Status -eq 'FAIL') { 'Red' } else { 'Yellow' }) }
  $liveRows = $null
  if ($Live) {
    $liveRows = Invoke-LiveCheck -Workbooks $WorkbookPath -Subs $Subscriptions
    foreach ($r in $liveRows) { Write-Host ("{0} | {1} | total={2} populated={3} {4}" -f $r.Type, $r.Path, $r.Total, $r.Populated, $r.Note) }
  }

  if ($ReportPath) {
    $md = [Collections.Generic.List[string]]::new()
    $md.Add('# Contract report'); $md.Add('')
    $md.Add("Run date: $(Get-Date -Format 'yyyy-MM-dd'). Specs: HybridCompute $HybridComputeVersion; AzureArcData $($ArcDataVersions -join ', '); SqlVirtualMachine $SqlVirtualMachineVersion; ARG tables: Learn supported-tables-resources."); $md.Add('')
    $md.Add('| Layer | Status | Count |'); $md.Add('| --- | --- | --- |')
    foreach ($g in ($findings | Group-Object Layer, Status | Sort-Object Name)) { $l, $s = $g.Name -split ', '; $md.Add("| $l | $s | $($g.Count) |") }
    $md.Add(''); $md.Add('| Status | Layer | Workbook | Item | Detail |'); $md.Add('| --- | --- | --- | --- | --- |')
    foreach ($f in ($findings | Sort-Object Status, Layer, Workbook, Item)) { $md.Add("| $($f.Status) | $($f.Layer) | $($f.Workbook) | $(($f.Item -replace '\|','/')) | $(($f.Detail -replace '\|','/')) |") }
    if ($liveRows) { $md.Add(''); $md.Add('| Type | Path | Total | Populated | Note |'); $md.Add('| --- | --- | --- | --- | --- |'); foreach ($l in $liveRows) { $md.Add("| $($l.Type) | $($l.Path) | $($l.Total) | $($l.Populated) | $($l.Note) |") } }
    [IO.File]::WriteAllText($ReportPath, (($md -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Write-Host "Report: $ReportPath"
  }
  $fails = @($findings | Where-Object Status -eq 'FAIL').Count
  Write-Host ("Contract check: {0} FAIL, {1} WARN, {2} UNVERIFIED, {3} DOCUMENTED, {4} OK/FREEFORM" -f $fails, @($findings | Where-Object Status -eq 'WARN').Count, @($findings | Where-Object Status -eq 'UNVERIFIED').Count, @($findings | Where-Object Status -eq 'DOCUMENTED').Count, @($findings | Where-Object { $_.Status -in 'OK', 'FREEFORM' }).Count)
  if ($fails) { exit 1 }
}
