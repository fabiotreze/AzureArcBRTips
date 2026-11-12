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
$aliasQuery = "resources | extend p = properties | extend s=tostring(p.status), a=p['agentVersion'], c=p.settings.architecture | where s == 'Expired'"
Assert-Equal ((Get-QueryPropertyPaths $aliasQuery | ForEach-Object Text | Sort-Object -Unique) -join ',') 'properties.agentVersion,properties.settings.architecture,properties.status' 'root property alias paths'
Assert-Equal ((Get-QueryEnumChecks $aliasQuery | ForEach-Object Literal) -join ',') 'Expired' 'enum through root property alias'
Assert-Equal (@(Get-QueryPropertyPaths "resources | extend p=properties | project x=other.p.status, y=somep.status").Count) 0 'alias does not match suffixes or nested fields'
Assert-Equal (Get-QueryTable 'resources') 'resources' 'table of a single-line query'
Assert-Equal (Get-QueryTable "// c`nAdvisorResources | take 1") 'advisorresources' 'table after comment, case-insensitive'
Assert-Equal (Get-QueryTable "// c`nresourcechanges | where properties.targetResourceType =~ 'microsoft.azurearcdata/sqlserverlicenses'") 'resourcechanges' 'table of a change-history query'
Assert-Equal ($script:DefensiveLiterals -contains 'properties.activationState=Active') $true 'defensive literals list'
Assert-Equal (Test-ArmPathInSpec -ArmPath '/providers/Microsoft.HybridCompute/osType/linux/agentVersions/latest' -Spec ([pscustomobject]@{ Files = @{ 'p.json' = @{ paths = @{ '/providers/Microsoft.HybridCompute/osType/{osType}/agentVersions/{version}' = @{ get = @{} } } } } })) '/providers/Microsoft.HybridCompute/osType/{osType}/agentVersions/{version}' 'ARM path template match'
Assert-Equal (Get-SourceNote -PathText 'properties.impactedField' -Types @('microsoft.resources/subscriptions', 'microsoft.advisor/recommendations')) 'Learn Resource Graph samples (Advisor, FinOps) and Advisor REST spec 2025-01-01' 'documented source, Advisor field'
Assert-Equal ([bool](Get-SourceNote -PathText 'properties.impactedField' -Types @('microsoft.policyinsights/policystates'))) $false 'source is scoped by resource type'
Assert-Equal ([bool](Get-SourceNote -PathText 'properties.settings.enableExtendedSecurityUpdates' -Types @('resourcechanges'))) $false 'free-form settings are never DOCUMENTED'
Assert-Equal ([bool](Get-SourceNote -PathText 'properties.hardwareProfile.vmSize' -Types @('microsoft.compute/virtualmachines'))) $true 'vmSize documented by Azure Policy alias'
Assert-Equal ($script:ObservedLiteralNotes.ContainsKey('properties.sqlServerLicenseType=NotSet')) $true 'observed note for NotSet literal'
Assert-Equal ($script:ObservedNotes.ContainsKey('properties.settings.ConsentToRecurringPAYG.Consented')) $true 'observed note for consent setting'

if ($script:fail) { Write-Host "$script:fail contract test(s) failed"; exit 1 }
Write-Host 'All contract tests passed'
