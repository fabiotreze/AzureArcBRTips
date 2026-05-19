<#
.SYNOPSIS
    Valida conectividade, DNS e funcionalidade de Azure Arc (Public ou Private Link).

.DESCRIPTION
    - Auto-detecta se o host usa Azure Arc Public ou Private Link Scope (PLS):
        1) tenta 'azcmagent show -j' e verifica o campo privateLinkScope
        2) fallback: resolve 'gbl.his.arc.azure.com' e classifica como Private se o IP for RFC1918
    - Testa DNS, TCP/443 e (para endpoints selecionados) HTTP.
    - Executa 'azcmagent check' com a flag correta conforme o modo.

.PARAMETER Region
    Região Azure (default: brazilsouth).

.PARAMETER Mode
    Auto | Public | Private. Default: Auto.

.PARAMETER LogFilePath
    Caminho do arquivo de log. Default: C:\temp\Arclogfile.txt.

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1
    Auto-detecta o modo (Public/Private) e usa a regiao default 'brazilsouth'.

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1 -Region eastus2
    Roda contra eastus2 com auto-deteccao do modo.

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1 -Region westeurope -Mode Public
    Forca modo Public na regiao westeurope (util pra validar lista de endpoints
    de internet quando o host ainda nao tem azcmagent instalado).

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1 -Region brazilsouth -Mode Private -LogFilePath D:\logs\arc-pls.txt
    Forca validacao Private Link e grava log em caminho customizado. Adiciona
    a flag '--enable-pls-check' ao 'azcmagent check'.

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1 -Region southcentralus -Verbose
    Roda com saida verbose detalhada. Outras regioes comuns:
    eastus, eastus2, westus2, westus3, centralus, northeurope, westeurope,
    uksouth, francecentral, switzerlandnorth, southeastasia, japaneast,
    australiaeast, brazilsouth, southafricanorth, uaenorth.

.NOTES
    Requer PowerShell 5.1+; azcmagent.exe é opcional (apenas para o check final).
    Codigo de saida: 0 = todos os testes OK; 1 = pelo menos uma falha.
#>

[CmdletBinding()]
param(
    [string]$Region = 'brazilsouth',

    [ValidateSet('Auto', 'Public', 'Private')]
    [string]$Mode = 'Auto',

    [string]$LogFilePath = 'C:\temp\Arclogfile.txt'
)

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # acelera Invoke-WebRequest e Test-NetConnection

$logDir = Split-Path -Path $LogFilePath -Parent
if ($logDir -and -not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
Set-Content -Path $LogFilePath -Value "Script started at $(Get-Date -Format o)" -Force

$script:Stats = [ordered]@{ OK = 0; Fail = 0 }
$script:LogBuffer = [System.Collections.Generic.List[string]]::new()
$script:Results = [System.Collections.Generic.Dictionary[string, object]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)] [string]$Endpoint,
        [string]$Field,
        $Value
    )
    if (-not $script:Results.ContainsKey($Endpoint)) {
        $script:Results[$Endpoint] = [ordered]@{
            Endpoint = $Endpoint
            IP       = '-'
            Type     = '-'
            DNS      = '-'
            TCP      = '-'
            HTTP     = '-'
        }
    }
    if ($Field) { $script:Results[$Endpoint][$Field] = $Value }
}

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('Info', 'OK', 'Fail', 'Warn')] [string]$Level = 'Info',
        [switch]$NoCount
    )
    $color = @{ Info = 'Gray'; OK = 'Green'; Fail = 'Red'; Warn = 'Yellow' }[$Level]
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format HH:mm:ss), $Level.ToUpper(), $Message
    Write-Host $line -ForegroundColor $color
    $script:LogBuffer.Add($line)

    if (-not $NoCount) {
        if ($Level -eq 'OK') { $script:Stats.OK++ }
        if ($Level -eq 'Fail') { $script:Stats.Fail++ }
    }
}

function Flush-Log {
    if ($script:LogBuffer.Count -gt 0) {
        Add-Content -Path $LogFilePath -Value $script:LogBuffer
        $script:LogBuffer.Clear()
    }
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory)] [string]$ComputerName,
        [int]$Port = 443,
        [int]$TimeoutMs = 3000
    )
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $iar = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
            $client.EndConnect($iar) | Out-Null
            return $true
        }
        return $false
    }
    catch { return $false }
    finally { $client.Close() }
}

# ---------------------------------------------------------------------------
# Detecção automática Public vs Private
# ---------------------------------------------------------------------------
function Get-AzcmagentPath {
    $candidate = Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Test-IsPrivateIp {
    param([string]$Ip)
    if (-not $Ip) { return $false }
    try {
        $bytes = ([System.Net.IPAddress]::Parse($Ip)).GetAddressBytes()
    }
    catch { return $false }

    # RFC1918 + 100.64/10 (CGNAT, comum em redes corporativas)
    return ($bytes[0] -eq 10) -or
    ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
    ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
    ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127)
}

function Resolve-ArcMode {
    Write-Log "Detectando modo Arc (Public/Private)..." Info -NoCount

    # 1) Via azcmagent show -j
    $azcm = Get-AzcmagentPath
    if ($azcm) {
        try {
            $json = & $azcm show -j 2>$null | ConvertFrom-Json
            $pls = $json.privateLinkScope
            if ($pls) {
                Write-Log "azcmagent reporta privateLinkScope: $pls" Info -NoCount
                return 'Private'
            }
            else {
                Write-Log "azcmagent nao reporta privateLinkScope (modo publico)." Info -NoCount
                return 'Public'
            }
        }
        catch {
            Write-Log "Falha ao consultar azcmagent show -j: $($_.Exception.Message). Caindo para fallback DNS." Warn
        }
    }
    else {
        Write-Log "azcmagent.exe nao encontrado. Usando fallback DNS." Warn
    }

    # 2) Fallback: resolver gbl.his.arc.azure.com
    try {
        $dns = Resolve-DnsName -Name 'gbl.his.arc.azure.com' -Type A -ErrorAction Stop
        $ip = ($dns | Where-Object IPAddress | Select-Object -First 1).IPAddress
        if (Test-IsPrivateIp -Ip $ip) {
            Write-Log "gbl.his.arc.azure.com resolve para IP privado ($ip) -> Private Link" Info -NoCount
            return 'Private'
        }
        else {
            Write-Log "gbl.his.arc.azure.com resolve para IP publico ($ip) -> Public" Info -NoCount
            return 'Public'
        }
    }
    catch {
        Write-Log "Nao foi possivel resolver gbl.his.arc.azure.com - assumindo Public." Warn
        return 'Public'
    }
}

if ($Mode -eq 'Auto') {
    $Mode = Resolve-ArcMode
}
Write-Log "Modo selecionado: $Mode | Regiao: $Region" Info -NoCount

# Reset stats: fase de testes comeca aqui (detecao nao conta)
$script:Stats.OK = 0
$script:Stats.Fail = 0

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
$staticEndpoints = @(
    'login.windows.net', 'login.microsoftonline.com', 'pas.windows.net',
    'management.azure.com',
    'global.handler.control.monitor.azure.com',
    'gbl.his.arc.azure.com', 'agentserviceapi.guestconfiguration.azure.com',
    "dataprocessingservice.$Region.arcdataservices.com",
    "telemetry.$Region.arcdataservices.com"
)

# Endpoints que respondem HTTP (validação extra)
$httpProbeEndpoints = @(
    'login.windows.net',
    'login.microsoftonline.com',
    "dataprocessingservice.$Region.arcdataservices.com",
    "telemetry.$Region.arcdataservices.com"
)

# Dynamic allowlist (somente em modo público; em PLS o tráfego é via PE)
$dynamicEndpoints = @()
if ($Mode -eq 'Public') {
    try {
        Write-Log "Buscando endpoints dinamicos do guestnotificationservice..." Info -NoCount
        $uri = "https://guestnotificationservice.azure.com/urls/allowlist?api-version=2020-01-01&location=$Region"
        $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop
        $dynamicEndpoints = @($resp.Content | ConvertFrom-Json) |
        Where-Object { $_ } |
        Select-Object -First 5
        Write-Log "Top 5 endpoints dinamicos: $($dynamicEndpoints -join ', ')" OK
    }
    catch {
        Write-Log "Falha ao obter endpoints dinamicos: $($_.Exception.Message)" Fail
    }
}
else {
    Write-Log "Modo Private: pulando consulta de allowlist publico." Info -NoCount
}

$allEndpoints = @($staticEndpoints + $dynamicEndpoints | Where-Object { $_ } | Select-Object -Unique)

# ---------------------------------------------------------------------------
# Testes: DNS + TCP/443 (validacao de coerencia com o modo detectado)
# ---------------------------------------------------------------------------
foreach ($ep in $allEndpoints) {
    $ep = $ep.Trim()
    $script:LogBuffer.Add('-' * 60)
    Add-Result -Endpoint $ep

    # DNS
    try {
        $dns = Resolve-DnsName -Name $ep -ErrorAction Stop
        $ip = ($dns | Where-Object IPAddress | Select-Object -First 1).IPAddress
        $kind = if (Test-IsPrivateIp -Ip $ip) { 'PRIVATE' } else { 'PUBLIC' }
        Add-Result -Endpoint $ep -Field 'IP'   -Value $ip
        Add-Result -Endpoint $ep -Field 'Type' -Value $kind

        # Alerta de mismatch DNS x modo
        $mismatch = ($Mode -eq 'Private' -and $kind -eq 'PUBLIC') -or `
        ($Mode -eq 'Public' -and $kind -eq 'PRIVATE')
        if ($mismatch) {
            Write-Log "DNS WARN $ep -> $ip [$kind] (esperado para modo $Mode era o oposto)" Warn
            Add-Result -Endpoint $ep -Field 'DNS' -Value 'WARN'
        }
        else {
            Write-Log "DNS OK   $ep -> $ip [$kind]" OK
            Add-Result -Endpoint $ep -Field 'DNS' -Value 'OK'
        }
    }
    catch {
        Write-Log "DNS FAIL $ep - $($_.Exception.Message)" Fail
        Add-Result -Endpoint $ep -Field 'DNS' -Value 'FAIL'
        continue
    }

    # TCP/443 (TcpClient com timeout - muito mais rapido que Test-NetConnection)
    if (Test-TcpPort -ComputerName $ep -Port 443 -TimeoutMs 5000) {
        Write-Log "TCP OK   ${ep}:443" OK
        Add-Result -Endpoint $ep -Field 'TCP' -Value 'OK'
    }
    else {
        Write-Log "TCP FAIL ${ep}:443 (timeout/recusado)" Fail
        Add-Result -Endpoint $ep -Field 'TCP' -Value 'FAIL'
    }
}

# ---------------------------------------------------------------------------
# Testes HTTP (401/403/400 sao considerados sucesso: endpoint exige auth)
# ---------------------------------------------------------------------------
foreach ($ep in $httpProbeEndpoints) {
    $script:LogBuffer.Add('-' * 60)
    $ep = $ep.Trim()
    Add-Result -Endpoint $ep
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-WebRequest -Uri "https://$ep" -Method Get -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $sw.Stop()
        Write-Log "HTTP OK  $ep -> $($resp.StatusCode) em $([math]::Round($sw.Elapsed.TotalSeconds,2))s" OK
        Add-Result -Endpoint $ep -Field 'HTTP' -Value "OK ($($resp.StatusCode))"
    }
    catch {
        $sw.Stop()
        # PS 5.1 -> WebException ; PS 7+ -> HttpResponseException ; ambos expoem .Response.StatusCode
        $code = $null
        if ($_.Exception.Response) {
            try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        }
        if ($code -in 400, 401, 403, 404) {
            Write-Log "HTTP OK  $ep -> $code (esperado sem auth/sem root handler)" OK
            Add-Result -Endpoint $ep -Field 'HTTP' -Value "OK ($code)"
        }
        elseif ($code) {
            Write-Log "HTTP FAIL $ep -> $code" Fail
            Add-Result -Endpoint $ep -Field 'HTTP' -Value "FAIL ($code)"
        }
        else {
            Write-Log "HTTP FAIL $ep - $($_.Exception.Message)" Fail
            Add-Result -Endpoint $ep -Field 'HTTP' -Value 'FAIL'
        }
    }
}

# ---------------------------------------------------------------------------
# azcmagent check
# ---------------------------------------------------------------------------
$script:LogBuffer.Add('=' * 60)
$azcm = Get-AzcmagentPath
if ($azcm) {
    $checkArgs = @('check', '--location', $Region, '--cloud', 'AzureCloud', '--extensions', 'sql')
    if ($Mode -eq 'Private') { $checkArgs += '--enable-pls-check' }

    Write-Log "Executando: azcmagent $($checkArgs -join ' ')" Info -NoCount
    Flush-Log   # garante ordem: cabecalho antes do output do binario
    try {
        $out = & $azcm @checkArgs 2>&1
        Add-Content -Path $LogFilePath -Value $out
        if ($LASTEXITCODE -eq 0) {
            Write-Log "azcmagent check concluido (exit 0)." OK
        }
        else {
            Write-Log "azcmagent check terminou com exit $LASTEXITCODE." Fail
        }
    }
    catch {
        Write-Log "azcmagent check falhou: $($_.Exception.Message)" Fail
    }
}
else {
    Write-Log "azcmagent.exe nao encontrado - pulando check." Warn
}

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
$script:LogBuffer.Add('=' * 60)
Write-Log ("Resumo: OK={0}  Fail={1}  Modo={2}  Regiao={3}" -f `
        $script:Stats.OK, $script:Stats.Fail, $Mode, $Region) Info -NoCount
Write-Log "Script finished at $(Get-Date -Format o)" Info -NoCount
Flush-Log

# ---------------------------------------------------------------------------
# Tabela de resultados (console + log)
# ---------------------------------------------------------------------------
$tableObjects = $script:Results.Values | ForEach-Object { [pscustomobject]$_ }
$tableString = $tableObjects | Format-Table -AutoSize | Out-String

Write-Host ""
Write-Host "================ SUMARIO ================" -ForegroundColor Cyan

# Console colorido por status
$rowFormat = "{0,-60} {1,-32} {2,-8} {3,-5} {4,-5} {5,-12}"
Write-Host ($rowFormat -f 'Endpoint', 'IP', 'Type', 'DNS', 'TCP', 'HTTP') -ForegroundColor Cyan
Write-Host ($rowFormat -f ('-' * 60), ('-' * 32), ('-' * 8), ('-' * 5), ('-' * 5), ('-' * 12)) -ForegroundColor DarkGray
foreach ($r in $tableObjects) {
    $hasFail = ($r.DNS -eq 'FAIL') -or ($r.TCP -eq 'FAIL') -or ($r.HTTP -like 'FAIL*')
    $hasWarn = ($r.DNS -eq 'WARN')
    $color = if ($hasFail) { 'Red' } elseif ($hasWarn) { 'Yellow' } else { 'Green' }
    Write-Host ($rowFormat -f $r.Endpoint, $r.IP, $r.Type, $r.DNS, $r.TCP, $r.HTTP) -ForegroundColor $color
}

Write-Host ""
Write-Host ("Totais: OK={0}  Fail={1}  Modo={2}  Regiao={3}" -f `
        $script:Stats.OK, $script:Stats.Fail, $Mode, $Region) -ForegroundColor Cyan

# Append tabela ao arquivo de log
Add-Content -Path $LogFilePath -Value ''
Add-Content -Path $LogFilePath -Value '================ SUMARIO ================'
Add-Content -Path $LogFilePath -Value $tableString.TrimEnd()
Add-Content -Path $LogFilePath -Value ("Totais: OK={0}  Fail={1}  Modo={2}  Regiao={3}" -f `
        $script:Stats.OK, $script:Stats.Fail, $Mode, $Region)

Write-Host "`nLog completo: $LogFilePath" -ForegroundColor Cyan
exit ([int]($script:Stats.Fail -gt 0))
