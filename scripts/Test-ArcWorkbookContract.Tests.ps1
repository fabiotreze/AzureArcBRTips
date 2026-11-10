#Requires -Version 7.0
<#
.SYNOPSIS
  Offline tests for Test-ArcWorkbookContract.ps1 (in-memory schemas; no network, no Azure).
  Testes offline do Test-ArcWorkbookContract.ps1 (schemas em memoria; sem rede, sem Azure).
.EXAMPLE
  pwsh -NoProfile -File .\scripts\Test-ArcWorkbookContract.Tests.ps1
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Test-ArcWorkbookContract.ps1')

$script:fail = 0
function Assert-Equal($Actual, $Expected, [string]$Name) {
  if ("$Actual" -ceq "$Expected") { Write-Host "[OK]   $Name" }
  else { Write-Host "[FAIL] $Name (expected '$Expected', got '$Actual')"; $script:fail++ }
}

$spec = [pscustomobject]@{
  Service = 'x'; Version = 'v'; Track = 'stable'
  Files = @{
    'a.json' = @{ definitions = @{
        Res   = @{ type = 'object'; properties = @{ properties = @{ '$ref' = '#/definitions/Props' } } }
        Props = @{ type = 'object'; allOf = @(@{ '$ref' = 'b.json#/definitions/Base' }); properties = @{
            status   = @{ type = 'string'; enum = @('Connected', 'Expired') }
            settings = @{ type = 'object' }
            nested   = @{ type = 'object'; properties = @{ list = @{ type = 'array'; items = @{ type = 'object'; properties = @{ id = @{ type = 'string' } } } } } }
          } }
      } }
    'b.json' = @{ definitions = @{ Base = @{ type = 'object'; properties = @{ agentVersion = @{ type = 'string' } } } } }
  }
}
$root = $spec.Files['a.json'].definitions.Res

function Get-Status($path) { (Find-SchemaPath -Root $root -File 'a.json' -Spec $spec -Segments ($path -split '\.')).Status }
Assert-Equal (Get-Status 'properties.status') 'Found' 'direct property'
Assert-Equal (Get-Status 'properties.agentVersion') 'Found' 'property from allOf in another file'
Assert-Equal (Get-Status 'properties.nested.list.id') 'Found' 'property through array items'
Assert-Equal (Get-Status 'properties.settings.Anything.Deep') 'Freeform' 'free-form object'
Assert-Equal (Get-Status 'properties.Status') 'CaseOnly' 'case mismatch'
Assert-Equal (Get-Status 'properties.agentVersionX') 'Missing' 'unknown property'
Assert-Equal ((Get-EnumValues (Find-SchemaPath -Root $root -File 'a.json' -Spec $spec -Segments 'properties', 'status').Leaf) -join ',') 'Connected,Expired' 'enum values'

$q = "resources`n| where type =~ 'microsoft.hybridcompute/machines'`n| extend s=tostring(properties.status), v=properties['agentVersion']`n| where s =~ 'Healthy' and properties.status in~ ('Connected','Expired')"
Assert-Equal ((Get-QueryPropertyPaths $q | ForEach-Object Text | Sort-Object -Unique) -join ',') 'properties.agentVersion,properties.status' 'property paths incl. bracket syntax'
Assert-Equal ((Get-QueryEnumChecks $q | ForEach-Object Literal | Sort-Object -Unique) -join ',') 'Connected,Expired,Healthy' 'enum literals incl. alias'
Assert-Equal (Get-QueryTypes $q) 'microsoft.hybridcompute/machines' 'type literal'
Assert-Equal (Get-QueryTable 'resources') 'resources' 'table of a single-line query'
Assert-Equal (Get-QueryTable "// c`nAdvisorResources | take 1") 'advisorresources' 'table after comment, case-insensitive'
Assert-Equal (Test-ArmPathInSpec -ArmPath '/providers/Microsoft.HybridCompute/osType/linux/agentVersions/latest' -Spec ([pscustomobject]@{ Files = @{ 'p.json' = @{ paths = @{ '/providers/Microsoft.HybridCompute/osType/{osType}/agentVersions/{version}' = @{ get = @{} } } } } })) '/providers/Microsoft.HybridCompute/osType/{osType}/agentVersions/{version}' 'ARM path template match'

if ($script:fail) { Write-Host "$script:fail contract test(s) failed"; exit 1 }
Write-Host 'All contract tests passed'
