#Requires -Version 7.0
<#
.SYNOPSIS
  Builds the Azure Connected Machine agent release calendar (version -> release date) from Microsoft sources.

.DESCRIPTION
  Two independent Microsoft sources are combined:
    1. "What's new with Azure Connected Machine agent" (Microsoft Learn): one section per release, "Version 1.69 - October 2026".
    2. The agent download host (gbl.his.arc.azure.com): the installer of each version answers HTTP 200 and its Last-Modified
       header is the publication date. Versions after the newest one in the release notes are probed too, so a build is
       detected as soon as Microsoft publishes it, before the notes page is updated.

  The result is written to a small JSON file that workbooks can read at run time (raw.githubusercontent.com sends CORS headers).
  The file is rewritten only when the calendar changes. If a source cannot be read or the data looks inconsistent, the script
  fails and leaves the existing file untouched. Read-only against Microsoft; no credentials needed.

.EXAMPLE
  ./scripts/Update-AgentReleases.ps1
  ./scripts/Update-AgentReleases.ps1 -OutFile ./agent-releases.json -Probe 3
#>
[CmdletBinding()]
param(
    [string]$OutFile = './workbooks/arc-agent-support/agent-releases.json',
    [string]$NotesUrl = 'https://learn.microsoft.com/en-us/azure/azure-arc/servers/agent-release-notes',
    [string]$DownloadUrlFormat = 'https://gbl.his.arc.azure.com/azcmagent/{0}/AzureConnectedMachineAgent.msi',
    [int]$Probe = 3,
    [int]$MinVersions = 12
)
$ErrorActionPreference = 'Stop'
$monthNumber = @{ January = 1; February = 2; March = 3; April = 4; May = 5; June = 6; July = 7; August = 8; September = 9; October = 10; November = 11; December = 12 }

function Invoke-Web([string]$Url, [string]$Method = 'Get') {
    for ($try = 1; $try -le 3; $try++) {
        try { return Invoke-WebRequest -UseBasicParsing -Uri $Url -Method $Method -SkipHttpErrorCheck -MaximumRedirection 5 -TimeoutSec 60 }
        catch { if ($try -eq 3) { throw "Cannot reach ${Url}: $($_.Exception.Message)" }; Start-Sleep -Seconds (2 * $try) }
    }
}

# 1) release notes -> version and month
$page = Invoke-Web $NotesUrl
if ([int]$page.StatusCode -ne 200) { throw "Release notes returned HTTP $([int]$page.StatusCode)" }
$text = [regex]::Replace($page.Content, '<script.*?</script>|<style.*?</style>', '', 'Singleline')
$text = [System.Net.WebUtility]::HtmlDecode([regex]::Replace($text, '<[^>]+>', ' ')) -replace '\s+', ' '
$notes = @{}
foreach ($m in [regex]::Matches($text, 'Version (\d+)\.(\d+) [–-] ([A-Z][a-z]+) (\d{4})')) {
    $name = $m.Groups[3].Value
    if (-not $monthNumber.ContainsKey($name)) { continue }
    $version = "$($m.Groups[1].Value).$($m.Groups[2].Value)"
    if (-not $notes.ContainsKey($version)) { $notes[$version] = '{0}-{1:00}' -f $m.Groups[4].Value, $monthNumber[$name] }
}
if ($notes.Count -lt $MinVersions) { throw "Only $($notes.Count) versions found in the release notes (expected at least $MinVersions); page layout may have changed." }

function Get-Rank([string]$v) { $p = $v -split '\.'; [int]$p[0] * 1000 + [int]$p[1] }
$ranks = @($notes.Keys | ForEach-Object { Get-Rank $_ } | Sort-Object)
for ($i = 1; $i -lt $ranks.Count; $i++) {
    if (($ranks[$i] / 1000 -as [int]) -eq ($ranks[$i - 1] / 1000 -as [int]) -and $ranks[$i] - $ranks[$i - 1] -ne 1) { throw "Release notes have a gap between rank $($ranks[$i - 1]) and $($ranks[$i]); refusing to publish." }
}

# 2) download host -> exists + publication date
function Get-Build([string]$Version) {
    $r = Invoke-Web ($DownloadUrlFormat -f $Version) 'Head'
    $code = [int]$r.StatusCode
    if ($code -eq 404) { return $null }
    if ($code -ne 200) { throw "Download host returned HTTP $code for $Version" }
    $lm = [string]($r.Headers['Last-Modified'] | Select-Object -First 1)
    $date = $null
    if ($lm) { $date = [datetime]::Parse($lm, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal).ToString('yyyy-MM-dd') }
    [pscustomobject]@{ Date = $date }
}

$entries = [System.Collections.Generic.List[object]]::new()
foreach ($v in $notes.Keys) {
    $b = Get-Build $v
    $entries.Add([pscustomobject]@{ Version = $v; Rank = (Get-Rank $v); Month = $notes[$v]; Released = $(if ($b -and $b.Date) { $b.Date } else { $null }); InNotes = $true; Downloadable = [bool]$b })
}
$top = ($entries | Measure-Object Rank -Maximum).Maximum
$major = [int]($top / 1000)
for ($n = 1; $n -le $Probe; $n++) {
    $rank = $top + $n; $v = '{0}.{1}' -f $major, ($rank % 1000)
    $b = Get-Build $v
    if (-not $b) { break }
    $month = if ($b.Date) { $b.Date.Substring(0, 7) } else { $null }
    $entries.Add([pscustomobject]@{ Version = $v; Rank = $rank; Month = $month; Released = $b.Date; InNotes = $false; Downloadable = $true })
}

# 3) consistency checks
foreach ($e in $entries) {
    if ($e.Released -and $e.Month -and $e.Released.Substring(0, 7) -ne $e.Month) { Write-Warning "Version $($e.Version): notes say $($e.Month) but the installer was published on $($e.Released)." }
}
$latest = $entries | Where-Object Downloadable | Sort-Object Rank -Descending | Select-Object -First 1
if (-not $latest) { throw 'No downloadable build found; refusing to publish.' }
$sorted = @($entries | Sort-Object Rank -Descending)

$content = [ordered]@{
    schemaVersion = 1
    description   = 'Azure Connected Machine agent release calendar (version, release date). Built from the Microsoft Learn release notes and the Microsoft agent download host.'
    sources       = [ordered]@{ releaseNotes = $NotesUrl; download = $DownloadUrlFormat }
    supportMonths = 12
    latest        = $latest.Version
    versions      = @($sorted | ForEach-Object { [ordered]@{ version = $_.Version; released = $(if ($_.Released) { $_.Released } else { $null }); month = $_.Month; inReleaseNotes = $_.InNotes; downloadable = $_.Downloadable } })
}

# 4) write only when something changed
$existing = $null
if (Test-Path -LiteralPath $OutFile) { try { $existing = Get-Content -LiteralPath $OutFile -Raw | ConvertFrom-Json -Depth 10 } catch { $existing = $null } }
$newCompare = ($content | ConvertTo-Json -Depth 10 -Compress)
$oldCompare = $null
if ($existing) { $copy = [ordered]@{}; foreach ($p in $existing.PSObject.Properties) { if ($p.Name -ne 'lastChangedUtc') { $copy[$p.Name] = $p.Value } }; $oldCompare = ($copy | ConvertTo-Json -Depth 10 -Compress) }
if ($oldCompare -ceq $newCompare) { Write-Host "No change. Latest build: $($content.latest); $($sorted.Count) versions."; return }
$final = [ordered]@{ lastChangedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
foreach ($k in $content.Keys) { $final[$k] = $content[$k] }
$dir = Split-Path -Parent $OutFile; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
[IO.File]::WriteAllText($OutFile, (($final | ConvertTo-Json -Depth 10) -replace "`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "Updated $OutFile. Latest build: $($content.latest); $($sorted.Count) versions ($(@($sorted | Where-Object { -not $_.InNotes }).Count) not yet in the release notes)."
