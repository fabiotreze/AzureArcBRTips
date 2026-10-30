#Requires -Version 7.0
<#
.SYNOPSIS
  End-to-end and scenario (matrix) test of the "Azure Arc – Agent Version Compliance" workbook.

.DESCRIPTION
  Reads the workbook JSON (no query is hard-coded here), resolves the workbook parameters the way the
  workbook does, and then:
    -Mode Smoke  : runs every parameter query and every visual once (defaults = what a user sees first).
    -Mode Matrix : Smoke + every filter value one-by-one, parameter variations (language, latest override,
                   support window, tolerance, fleet max) and every extension drill-down with 3 targets
                   (latest / oldest published / invalid). After each scenario it checks LOGICAL INVARIANTS
                   (totals add up, partitions sum to the baseline, overrides behave as expected, ...).
  Read-only: only Azure Resource Graph queries and ARM GET calls.

.EXAMPLE
  Connect-AzAccount
  .\Test-ArcAgentSupportWorkbook.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Mode Matrix -OutFolder .\wb-test
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkbookPath,
    [ValidateSet('Smoke','Matrix')][string]$Mode = 'Matrix',
    [string[]]$SubscriptionId,
    [string]$OutFolder = '.\workbook-test',
    [int]$ThrottleDelayMs = 350,
    [int]$MaxExtensions = 50
)
$ErrorActionPreference = 'Stop'
foreach ($m in 'Az.Accounts','Az.ResourceGraph') { if (-not (Get-Module -ListAvailable $m)) { throw "Module $m not found. Install-Module $m" } }
if (-not (Get-AzContext)) { throw 'Run Connect-AzAccount first.' }
New-Item -ItemType Directory -Force -Path $OutFolder | Out-Null

$wb        = Get-Content -Raw -Path $WorkbookPath | ConvertFrom-Json
$allParams = @($wb.items | Where-Object type -eq 9 | ForEach-Object { $_.content.parameters })
$visuals   = @($wb.items | Where-Object type -eq 3)
$StepLog   = [System.Collections.Generic.List[object]]::new()
$Checks    = [System.Collections.Generic.List[object]]::new()

#region ---------- helpers ----------
function Resolve-Text([string]$text, [hashtable]$pv) {
    [regex]::Replace($text, '\{([A-Za-z_][A-Za-z0-9_]*)\}', { param($m) $n = $m.Groups[1].Value; if ($pv.ContainsKey($n)) { [string]$pv[$n] } else { $m.Value } })
}
function Get-Unresolved([string]$text, [hashtable]$pv) {
    @([regex]::Matches($text, '\{([A-Za-z_][A-Za-z0-9_]*)\}') | ForEach-Object { $_.Groups[1].Value } | Where-Object { -not $pv.ContainsKey($_) } | Select-Object -Unique)
}
function Invoke-Arg([string]$query) {
    $all = [System.Collections.Generic.List[object]]::new(); $skip = $null
    do {
        $a = @{ Query = $query; First = 1000 }
        if ($SubscriptionId) { $a.Subscription = $SubscriptionId } else { $a.UseTenantScope = $true }
        if ($skip) { $a.SkipToken = $skip }
        $r = Search-AzGraph @a
        foreach ($x in @($r.Data ?? $r)) { $all.Add($x) }
        $skip = $r.SkipToken
    } while ($skip)
    , $all.ToArray()
}
function Get-JsonPathValue($obj, [string]$path) {
    $cur = $obj
    foreach ($seg in ($path -replace '^\$\.?','').Split('.', [StringSplitOptions]::RemoveEmptyEntries)) {
        if ($null -eq $cur) { break }
        if ($seg -match '^(\w+)\[\*\]$') { $cur = @($cur.($Matches[1])) }
        elseif ($seg -match '^(\w+)\[(\d+)\]$') { $cur = $cur.($Matches[1])[[int]$Matches[2]] }
        elseif ($cur -is [array]) { $cur = @($cur | ForEach-Object { $_.$seg }) }
        else { $cur = $cur.$seg }
    }
    if ($cur -is [array]) { ($cur | ConvertTo-Json -Compress -AsArray) } else { $cur }
}
function Invoke-Arm([string]$armJson, [hashtable]$pv) {
    $def  = Resolve-Text $armJson $pv | ConvertFrom-Json
    $qs   = ($def.urlParams | ForEach-Object { "$($_.key)=$($_.value)" }) -join '&'
    $resp = Invoke-AzRestMethod -Method GET -Path ("{0}?{1}" -f $def.path, $qs)
    if ($resp.StatusCode -ge 400) { throw "HTTP $($resp.StatusCode): $(($resp.Content -split "`n")[0])" }
    $body = $resp.Content | ConvertFrom-Json
    $t    = $def.transformers[0].settings
    $rows = if ($t.tablePath -eq '$') { , $body }
            elseif ($t.tablePath -match '^\$\.value\[\?\(@\.(\w+) >= ''(.*)''\)\]$') { $f=$Matches[1]; $v=$Matches[2]; @($body.value | Where-Object { [string]::CompareOrdinal([string]$_.$f, $v) -ge 0 }) }
            else { @($body.value) }
    $out = foreach ($r in $rows) { $o = [ordered]@{}; foreach ($c in $t.columns) { $o[$c.columnid] = Get-JsonPathValue $r $c.path }; [pscustomobject]$o }
    [pscustomobject]@{ Rows = @($out); NextLink = $body.nextLink }
}
function Run-Step([string]$scenario, [string]$name, [string]$kind, [scriptblock]$run) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); $status = 'Pass'; $err = ''; $rows = @(); $note = ''
    try {
        $r = & $run
        if ($r -is [pscustomobject] -and $r.PSObject.Properties['NextLink']) { if ($r.NextLink) { $note = 'paged (first page only, as in workbook)' }; $r = $r.Rows }
        $rows = @($r)
        if ($rows.Count -eq 0) { $status = 'Pass (0 rows)' }
    } catch { $status = 'FAIL'; $err = ($_.Exception.Message -split "`n")[0] }
    $sw.Stop()
    $StepLog.Add([pscustomobject]@{ Scenario=$scenario; Step=$name; Type=$kind; Status=$status; Rows=$rows.Count; Ms=$sw.ElapsedMilliseconds; Note=$note; Error=$err })
    Start-Sleep -Milliseconds $ThrottleDelayMs
    , $rows
}
function Check([string]$scenario, [string]$rule, [bool]$ok, [string]$detail) {
    $Checks.Add([pscustomobject]@{ Scenario=$scenario; Rule=$rule; Result=$(if ($ok) {'OK'} else {'BUG?'}); Detail=$detail })
}
function Num($v) { if ($null -eq $v -or "$v" -eq '') { 0 } else { [double]$v } }
function SumCol($rows, $col) { $s = 0; foreach ($r in @($rows)) { $s += Num $r.$col }; $s }
function Tile($data, [int]$n) { $r = @($data["kpi-tile-$n"]); if ($r.Count) { Num $r[0].Value } else { $null } }
#endregion

#region ---------- baseline parameter resolution ----------
$base = @{}
foreach ($p in $allParams) {
    if ($p.type -eq 2 -and $p.multiSelect -and $p.typeSettings.selectAllValue) { $base[$p.name] = "'All'" }
    elseif ($p.PSObject.Properties['value'] -and $p.value -isnot [array] -and $null -ne $p.value) { $base[$p.name] = [string]$p.value }
    elseif ($p.type -eq 1 -and -not $p.query) { $base[$p.name] = '' }
}
$base['Subscriptions'] = ''
$domain = @{}   # discovered values for dropdown filters
foreach ($p in $allParams | Where-Object { $_.query }) {
    if ($p.name -like 'Ext*') { continue }   # drill-down params are resolved per extension
    $miss = Get-Unresolved $p.query $base
    if ($miss) { $StepLog.Add([pscustomobject]@{Scenario='baseline';Step="param:$($p.name)";Type='Param';Status='SKIP';Rows=0;Ms=0;Note="needs $($miss -join ',')";Error=''}); continue }
    if ($p.queryType -eq 12) {
        $r = Run-Step 'baseline' "param:$($p.name)" 'Param/ARM' { Invoke-Arm $p.query $base }
        $vals = @($r | ForEach-Object { $_.PSObject.Properties.Value | Select-Object -First 1 })
        if ($p.type -eq 2) { $base[$p.name] = ($vals -join ',') } else { $base[$p.name] = [string]($vals | Select-Object -First 1) }
    } else {
        $r = Run-Step 'baseline' "param:$($p.name)" 'Param/ARG' { Invoke-Arg (Resolve-Text $p.query $base) }
        if ($p.type -eq 2) {
            $domain[$p.name] = @($r | ForEach-Object value | Where-Object { $_ })
            if (-not $p.typeSettings.selectAllValue) { $base[$p.name] = (@($r | ForEach-Object { "'" + $_.value + "'" }) -join ',') }
        } else {
            $first = @($r)[0]; $base[$p.name] = if ($first) { [string]($first.PSObject.Properties | Select-Object -First 1).Value } else { '' }
        }
    }
}
foreach ($p in $allParams | Where-Object { $_.type -eq 2 -and $_.jsonData -and $_.multiSelect }) { $domain[$p.name] = @($p.jsonData | ConvertFrom-Json) }
#endregion

#region ---------- scenario runner ----------
$agentVisuals = @($visuals | Where-Object { $_.name -notlike 'ext-*' -or $_.name -eq 'ext-issues' })
function Run-Scenario([string]$scenario, [hashtable]$over) {
    $pv = $base.Clone(); foreach ($k in $over.Keys) { $pv[$k] = $over[$k] }
    $data = @{}
    foreach ($it in $agentVisuals) {
        $q = $it.content.query
        if (Get-Unresolved $q $pv) { continue }
        if ($it.content.queryType -eq 12) { $data[$it.name] = Run-Step $scenario $it.name 'Visual/ARM' { Invoke-Arm $q $pv } }
        else { $data[$it.name] = Run-Step $scenario $it.name 'Visual/ARG' { Invoke-Arg (Resolve-Text $q $pv) } }
    }
    # ---- invariants valid for every scenario
    $total = Tile $data 1
    if ($null -ne $total) {
        $parts = (Tile $data 2) + (Tile $data 3) + (Tile $data 4) + (Tile $data 5)
        Check $scenario 'Tiles: Latest+Supported+Out of support+Unknown = Total' ($parts -eq $total) "$parts vs $total"
        foreach ($pie in 'pie-support','pie-conn','pie-auto','pie-health') { if ($data.ContainsKey($pie)) { $s = SumCol $data[$pie] 'Servers'; Check $scenario "$pie sum = Total" ($s -eq $total) "$s vs $total" } }
        foreach ($bar in 'bar-version','bar-support-conn','au-summary') { if ($data.ContainsKey($bar)) { $s = SumCol $data[$bar] 'Servers'; Check $scenario "$bar sum = Total" ($s -eq $total) "$s vs $total" } }
        foreach ($tbl in 'inventory','au-detail') { if ($data.ContainsKey($tbl)) { $c = @($data[$tbl]).Count; Check $scenario "$tbl rows = Total" ($c -eq $total) "$c vs $total" } }
        if ($data.ContainsKey('upgrade-paths')) { $s = SumCol $data['upgrade-paths'] 'Machines'; Check $scenario 'upgrade-paths Machines = Total' ($s -eq $total) "$s vs $total" }
        if ($data.ContainsKey('adv-xcheck')) { $s = SumCol $data['adv-xcheck'] 'Servers'; Check $scenario 'adv-xcheck sum = Total' ($s -eq $total) "$s vs $total" }
        $conn = Tile $data 6; $auOn = Tile $data 7; $onTr = Tile $data 8
        Check $scenario 'Connected <= Total' ($conn -le $total) "$conn vs $total"
        Check $scenario 'Auto-upgrade on track <= enabled' ($onTr -le $auOn) "$onTr vs $auOn"
        if ($data.ContainsKey('inventory')) {
            $bad = @($data['inventory'] | Where-Object { $_.SupportStatus -eq 'Latest' -and (Num $_.VersionsBehind) -ne 0 })
            Check $scenario 'Inventory: Latest => VersionsBehind = 0' ($bad.Count -eq 0) "$($bad.Count) rows"
            $win = [int](Resolve-Text '{SupportWindow}' $pv)
            $bad = @($data['inventory'] | Where-Object { $_.SupportStatus -eq 'Supported' -and (Num $_.VersionsBehind) -ge $win })
            Check $scenario 'Inventory: Supported => VersionsBehind < SupportWindow' ($bad.Count -eq 0) "$($bad.Count) rows"
            $bad = @($data['inventory'] | Where-Object { $_.SupportStatus -eq 'Out of support' -and (Num $_.VersionsBehind) -lt $win })
            Check $scenario 'Inventory: Out of support => VersionsBehind >= SupportWindow' ($bad.Count -eq 0) "$($bad.Count) rows"
            $bad = @($data['inventory'] | Where-Object { $_.ConnectionStatus -ne 'Connected' -and $_.VersionFreshness -eq 'Live' })
            Check $scenario 'Inventory: not Connected => version flagged stale' ($bad.Count -eq 0) "$($bad.Count) rows"
        }
        if ($data.ContainsKey('inventory') -and $null -ne (Tile $data 12)) {
            $below = @($data['inventory'] | Where-Object SecurityFloor -eq 'Below security floor')
            Check $scenario 'Security floor tile = inventory rows below floor' ((Tile $data 12) -eq $below.Count) "$((Tile $data 12)) vs $($below.Count)"
            $fl = Resolve-Text '{SecurityFloorVersion}' $pv
            if ($fl -match '^(\d+)\.(\d+)') {
                $fr = [int]$Matches[1] * 1000 + [int]$Matches[2]
                $bad = @($data['inventory'] | Where-Object { $_.AgentVersion -match '^(\d+)\.(\d+)' -and (([int]$Matches[1] * 1000 + [int]$Matches[2]) -lt $fr) -ne ($_.SecurityFloor -eq 'Below security floor') })
                Check $scenario 'Security floor flag matches agent version' ($bad.Count -eq 0) "$($bad.Count) rows"
            }
            if ($data.ContainsKey('upgrade-paths')) {
                $bad = @($data['upgrade-paths'] | Where-Object { $_.Installed -match '^(\d+)\.(\d+)' -and $fl -match '^(\d+)\.(\d+)' -and $_.Action -ne 'Upgrade now (below security floor)' -and ([version]$_.Installed -lt [version]$fl) })
                Check $scenario 'Upgrade paths: below floor => Upgrade now (below security floor)' ($bad.Count -eq 0) "$($bad.Count) rows"
            }
        }
        if ($data.ContainsKey('au-detail')) {
            $tol = [int](Resolve-Text '{AutoUpgradeTolerance}' $pv)
            $bad = @($data['au-detail'] | Where-Object { $_.UpgradeHealth -eq 'On track' -and ($_.AutoUpgrade -ne 'Enabled' -or $_.ConnectionStatus -ne 'Connected' -or $_.LastAttemptStatus -eq 'Failed' -or (Num $_.VersionsBehind) -gt $tol) })
            Check $scenario 'Auto-upgrade: On track => Enabled, connected, no failed attempt, behind <= tolerance' ($bad.Count -eq 0) "$($bad.Count) rows"
            $bad = @($data['au-detail'] | Where-Object { $_.AutoUpgrade -eq 'Enabled' -and $_.LastAttemptStatus -eq 'Failed' -and $_.AgentVersion -and $_.UpgradeHealth -ne 'Failing' })
            Check $scenario 'Auto-upgrade: failed last attempt => Failing' ($bad.Count -eq 0) "$($bad.Count) rows"
            $bad = @($data['au-detail'] | Where-Object { $_.AutoUpgrade -eq 'Enabled' -and $_.ConnectionStatus -ne 'Connected' -and $_.LastAttemptStatus -ne 'Failed' -and $_.AgentVersion -and $_.UpgradeHealth -ne 'Blocked (not connected)' })
            Check $scenario 'Auto-upgrade: offline without failed attempt => Blocked' ($bad.Count -eq 0) "$($bad.Count) rows"
            $bad = @($data['au-detail'] | Where-Object { $_.UpgradeHealth -like 'Disabled*' -and $_.AutoUpgrade -eq 'Enabled' })
            Check $scenario 'Auto-upgrade: Disabled (eligible) => not Enabled' ($bad.Count -eq 0) "$($bad.Count) rows"
        }
        if ($data.ContainsKey('adv-summary')) {
            $bad = @($data['adv-summary'] | Where-Object { $_.ActiveResources -match '^(\d+) of (\d+)' -and [int]$Matches[1] -gt [int]$Matches[2] })
            Check $scenario 'Advisor: affected <= total machines' ($bad.Count -eq 0) "$($bad.Count) rows"
        }
        if ($data.ContainsKey('extensions') -and $data.ContainsKey('ext-issues')) {
            foreach ($e in @($data['extensions'])) {
                $f = SumCol @($data['ext-issues'] | Where-Object { $_.Extension -eq $e.ExtensionType -and $_.IssueCategory -eq 'Failure' }) 'Servers'
                if ((Num $e.Failed) -ne $f) { Check $scenario "Extensions: Failed($($e.ExtensionType)) = issues Failure" $false "$($e.Failed) vs $f" }
            }
            Check $scenario 'Extensions: Failed counts match issue table (all extensions)' $true 'see BUG? rows above if any'
        }
        if ($data.ContainsKey('policy')) {
            $bad = @($data['policy'] | Where-Object { (Num $_.NonCompliantMachines) + (Num $_.CompliantMachines) + (Num $_.OtherMachines) -ne (Num $_.EvaluatedMachines) })
            Check $scenario 'Policy: NonCompliant+Compliant+Other = Evaluated' ($bad.Count -eq 0) "$($bad.Count) rows"
        }
    }
    $data
}
#endregion

#region ---------- scenarios ----------
Write-Host 'Scenario: baseline' -ForegroundColor Cyan
$B = Run-Scenario 'baseline' @{}
$T0 = Tile $B 1
if ($Mode -eq 'Matrix') {
    # 1) every filter value one-by-one + partition check (sum over values = baseline)
    foreach ($f in 'OsFilter','StatusFilter','SupportFilter','AutoUpgradeFilter') {
        $sum = 0
        foreach ($v in @($domain[$f])) {
            $sc = "$f=$v"; Write-Host "Scenario: $sc" -ForegroundColor Cyan
            $d = Run-Scenario $sc @{ $f = "'$v'" }
            $t = Tile $d 1; $sum += $t
            Check $sc 'Filtered total <= baseline' ($t -le $T0) "$t vs $T0"
            if ($f -eq 'SupportFilter') { $col = @{ 'Latest'=2;'Supported'=3;'Out of support'=4;'Unknown'=5 }[$v]; if ($col) { Check $sc "Support filter: only '$v' remains" ((Tile $d $col) -eq $t) "$((Tile $d $col)) vs $t" } }
            if ($f -eq 'StatusFilter') { $bad = @($d['inventory'] | Where-Object ConnectionStatus -ne $v); Check $sc 'Status filter applied to inventory' ($bad.Count -eq 0) "$($bad.Count) rows"
                                         $bad = @($d['adv-detail'] | Where-Object ConnectionStatus -ne $v); Check $sc 'Status filter applied to Advisor detail' ($bad.Count -eq 0) "$($bad.Count) rows" }
            if ($f -eq 'OsFilter') { $bad = @($d['inventory'] | Where-Object OS -ne $v); Check $sc 'OS filter applied to inventory' ($bad.Count -eq 0) "$($bad.Count) rows"
                                     $ext = SumCol $d['extensions'] 'Machines'; $extB = SumCol $B['extensions'] 'Machines'; Check $sc 'OS filter reduces extension rows' ($ext -le $extB) "$ext vs $extB" }
        }
        Check "partition:$f" "Sum over all $f values = baseline total" ($sum -eq $T0) "$sum vs $T0"
    }
    # 2) multi-value filter (first two values together)
    $os = @($domain['StatusFilter']); if ($os.Count -ge 2) {
        $sc = "StatusFilter=$($os[0])+$($os[1])"; Write-Host "Scenario: $sc" -ForegroundColor Cyan
        $d = Run-Scenario $sc @{ StatusFilter = "'$($os[0])','$($os[1])'" }
        $exp = (@($B['inventory'] | Where-Object { $_.ConnectionStatus -in $os[0], $os[1] })).Count
        Check $sc 'Multi-select status = sum of both values' ((Tile $d 1) -eq $exp) "$((Tile $d 1)) vs $exp"
    }
    # 3) parameter variations
    $runs = [ordered]@{
        'Language=PT'          = @{ Language = 'PT' }
        'IncludeFleetMax=Yes'  = @{ IncludeFleetMax = 'Yes' }
        'SupportWindow=100'    = @{ SupportWindow = '100' }
        'SupportWindow=1'      = @{ SupportWindow = '1' }
        'AutoUpgradeTolerance=0' = @{ AutoUpgradeTolerance = '0' }
        'LatestOverride=99.0'  = @{ LatestOverride = '99.0' }
        'LatestOverride=1.0'   = @{ LatestOverride = '1.0' }
        'LatestOverride=abc'   = @{ LatestOverride = 'abc' }
        'MinAutoUpgradeVersion=99.0' = @{ MinAutoUpgradeVersion = '99.0' }
        'SecurityFloorVersion=99.0' = @{ SecurityFloorVersion = '99.0' }
        'SecurityFloorVersion=1.0'  = @{ SecurityFloorVersion = '1.0' }
        'SecurityFloorVersion=empty' = @{ SecurityFloorVersion = '' }
    }
    foreach ($k in $runs.Keys) {
        Write-Host "Scenario: $k" -ForegroundColor Cyan
        $d = Run-Scenario $k $runs[$k]
        switch ($k) {
            'Language=PT'         { for ($i=1;$i -le 12;$i++){ if ((Tile $d $i) -ne (Tile $B $i)) { Check $k "Tile $i equal in EN and PT" $false "$((Tile $d $i)) vs $((Tile $B $i))" } }; Check $k 'All tiles equal in EN and PT' $true '' }
            'IncludeFleetMax=Yes' { Check $k 'Fleet max as source cannot reduce Latest reference (Out of support not lower than baseline... informative)' $true "Latest $((Tile $d 2)) vs baseline $((Tile $B 2))" }
            'SupportWindow=100'   { Check $k 'Window 100 => Out of support = 0' ((Tile $d 4) -eq 0) "$((Tile $d 4))" }
            'SupportWindow=1'     { Check $k 'Window 1 => Supported = 0' ((Tile $d 3) -eq 0) "$((Tile $d 3))" }
            'AutoUpgradeTolerance=0' { Check $k 'Tolerance 0 => on track <= baseline' ((Tile $d 8) -le (Tile $B 8)) "$((Tile $d 8)) vs $((Tile $B 8))" }
            'LatestOverride=99.0' { Check $k 'Override above all => Latest = 0' ((Tile $d 2) -eq 0) "$((Tile $d 2))"
                                    $bad = @($d['official-vs-fleet'] | Where-Object Source -ne 'Manual override'); Check $k 'Override => source = Manual override' ($bad.Count -eq 0) "$($bad.Count) rows" }
            'LatestOverride=1.0'  { Check $k 'Override below all => everyone Latest' ((Tile $d 2) -eq ((Tile $d 1) - (Tile $d 5))) "$((Tile $d 2)) vs $((Tile $d 1) - (Tile $d 5))" }
            'LatestOverride=abc'  { Check $k 'Invalid override ignored (= baseline)' ((Tile $d 2) -eq (Tile $B 2)) "$((Tile $d 2)) vs $((Tile $B 2))" }
            'MinAutoUpgradeVersion=99.0' { Check $k 'Min 99 => nobody eligible-but-disabled' ((Tile $d 10) -eq 0) "$((Tile $d 10))" }
            'SecurityFloorVersion=99.0' { Check $k 'Floor 99 => every known version below floor' ((Tile $d 12) -eq ((Tile $d 1) - (Tile $d 5))) "$((Tile $d 12)) vs $((Tile $d 1) - (Tile $d 5))" }
            'SecurityFloorVersion=1.0'  { Check $k 'Floor 1.0 => nobody below floor' ((Tile $d 12) -eq 0) "$((Tile $d 12))" }
            'SecurityFloorVersion=empty' { Check $k 'Empty floor => not evaluated (0 below)' ((Tile $d 12) -eq 0) "$((Tile $d 12))" }
        }
    }
}
# 4) extension drill-down (simulated clicks) – every extension, 3 targets
$detail = $visuals | Where-Object name -eq 'ext-detail'; $avail = $visuals | Where-Object name -eq 'ext-available'
$pA = $allParams | Where-Object name -eq 'ExtAvailable'; $pJ = $allParams | Where-Object name -eq 'ExtAvailableJson'
$exts = @($B['extensions']) | Select-Object -First $(if ($Mode -eq 'Matrix') { $MaxExtensions } else { 1 })
foreach ($e in $exts) {
    $sc = "ext:$($e.ExtensionType)"; Write-Host "Scenario: $sc" -ForegroundColor Cyan
    $pv = $base.Clone(); $pv['ExtPublisher'] = $e.Publisher; $pv['ExtType'] = $e.ExtensionType; $pv['ExtLocation'] = $e.Location
    $ra = Run-Step $sc 'param:ExtAvailable' 'Param/ARM' { Invoke-Arm $pA.query $pv }; $pv['ExtAvailable'] = (@($ra | ForEach-Object value) -join ',')
    if ($pJ) { $rj = Run-Step $sc 'param:ExtAvailableJson' 'Param/ARM' { Invoke-Arm $pJ.query $pv }; $pv['ExtAvailableJson'] = [string](@($rj)[0].v) }
    $pub = Run-Step $sc 'ext-available' 'Visual/ARG' { Invoke-Arg (Resolve-Text $avail.content.query $pv) }
    Check $sc 'Published list: machines sum = extension machines' ((SumCol $pub 'Machines') -eq (Num $e.Machines)) "$((SumCol $pub 'Machines')) vs $($e.Machines)"
    $versions = @($pub | Where-Object PublishedByAzure -eq 'Yes' | ForEach-Object Version)
    $targets = [ordered]@{ latest = 'latest'; oldest = ($versions | Select-Object -Last 1); invalid = '9.9.9.9' }
    foreach ($tk in $targets.Keys) {
        if (-not $targets[$tk]) { continue }
        $pv['ExtTargetVersion'] = $targets[$tk]
        $rows = Run-Step $sc "ext-detail (target=$tk)" 'Visual/ARG' { Invoke-Arg (Resolve-Text $detail.content.query $pv) }
        Check "$sc/$tk" 'Per-server rows = extension machines' ($rows.Count -eq (Num $e.Machines)) "$($rows.Count) vs $($e.Machines)"
        $bad = @($rows | Where-Object { (Num $_.BehindTarget) -gt (Num $_.BehindLatest) }); Check "$sc/$tk" 'BehindTarget <= BehindLatest' ($bad.Count -eq 0) "$($bad.Count) rows"
        $bad = @($rows | Where-Object { $_.VersionStatus -eq 'Latest' -and (Num $_.BehindLatest) -ne 0 }); Check "$sc/$tk" 'Latest => BehindLatest = 0' ($bad.Count -eq 0) "$($bad.Count) rows"
        if ($tk -ne 'oldest') { $bad = @($rows | Where-Object { $_.Target -notlike '*(latest)' -and $versions.Count }); Check "$sc/$tk" 'latest/invalid target => compare with latest' ($bad.Count -eq 0) "$($bad.Count) rows" }
        else { $bad = @($rows | Where-Object { $_.VersionStatus -eq 'Below target' -and $_.ProvisioningState -eq 'Succeeded' -and $_.InstalledVersion -eq $targets[$tk] }); Check "$sc/$tk" 'Installed = target is never Below target' ($bad.Count -eq 0) "$($bad.Count) rows" }
        $bad = @($rows | Where-Object { $_.ProvisioningState -eq 'Failed' -and $_.IssueCategory -ne 'Failure' }); Check "$sc/$tk" 'Failed => IssueCategory Failure' ($bad.Count -eq 0) "$($bad.Count) rows"
    }
}
#endregion

#region ---------- report ----------
$fails = @($StepLog | Where-Object Status -eq 'FAIL'); $bugs = @($Checks | Where-Object Result -ne 'OK')
$StepLog | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $OutFolder 'steps.csv')
$Checks  | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $OutFolder 'checks.csv')
Write-Host "`n=== Query execution ===" -ForegroundColor Yellow
$StepLog | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize
if ($fails) { Write-Host 'FAILED queries:' -ForegroundColor Red; $fails | Format-Table Scenario, Step, Error -AutoSize -Wrap }
Write-Host "=== Logical checks: $($Checks.Count) run, $($bugs.Count) possible bugs ===" -ForegroundColor Yellow
if ($bugs) { $bugs | Format-Table Scenario, Rule, Detail -AutoSize -Wrap } else { Write-Host 'All invariants hold.' -ForegroundColor Green }
Write-Host "Reports: $(Join-Path $OutFolder 'steps.csv') | $(Join-Path $OutFolder 'checks.csv')"
#endregion
