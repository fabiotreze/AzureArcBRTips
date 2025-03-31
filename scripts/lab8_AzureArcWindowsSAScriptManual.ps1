# Definir variáveis iniciais
$subscriptionId = 'YourSubscriptionID' # Seu ID da assinatura
$location = "BrazilSouth" # Região onde as máquinas estão registradas no Azure Arc

# Conectar ao Azure
$account = Connect-AzAccount
$context = Set-AzContext -Subscription $subscriptionId

# Buscar lista de máquinas não ativadas no Azure Resource Graph
$query = @"
resources
| where type =~ "microsoft.hybridcompute/machines"
| extend status = properties.status
| extend operatingSystem = properties.osSku
| where properties.osType =~ 'windows'
| extend licenseProfile = coalesce(properties.licenseProfile, properties.licenseProfileStorage.properties)
| extend licenseStatus = tostring(licenseProfile.licenseStatus)
| extend licenseChannel = tostring(licenseProfile.licenseChannel)
| extend productSubscriptionStatus = tostring(licenseProfile.productProfile.subscriptionStatus)
| extend softwareAssurance = licenseProfile.softwareAssurance
| extend softwareAssuranceCustomer = licenseProfile.softwareAssurance.softwareAssuranceCustomer
| extend benefitsStatus = case(
    softwareAssuranceCustomer == true, "Activated",
    (licenseStatus =~ "Licensed" and licenseChannel =~ "PGS:TB") or productSubscriptionStatus =~ "Enabled", "Activated via Pay-as-you-go",
    isnull(softwareAssurance) or isnull(softwareAssuranceCustomer) or softwareAssuranceCustomer == false, "Not activated",
    "Not activated")
| where (benefitsStatus =~ 'Not activated')
| where (operatingSystem !~ ('windows 11 enterprise'))
| where (type in~ ('Microsoft.HybridCompute/machinesSoftwareAssurance','Microsoft.HybridCompute/machines'))
| project name, resourceGroup, subscriptionId, operatingSystem, location
"@

Write-Host "Executando consulta no Azure Resource Graph..."
$result = Search-AzGraph -Query $query

# Garantir que os resultados sejam armazenados como um array
$machines = @()
if ($result) {
    $machines = $result
}

# Verificar se há máquinas retornadas
if ($machines.Count -eq 0) {
    Write-Host "Nenhuma máquina não ativada encontrada!"
    exit
}

# Obter token de autenticação para a API REST
$profile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = [Microsoft.Azure.Commands.ResourceManager.Common.rmProfileClient]::new($profile)
$token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)

$header = @{
    'Content-Type'  = 'application/json'
    'Authorization' = 'Bearer ' + $token.AccessToken
}

# Loop para processar cada máquina
foreach ($machine in $machines) {
    $machineName = $machine.name
    $resourceGroupName = $machine.resourceGroup
    $subscriptionId = $machine.subscriptionId

    Write-Host "`n🔹 Processando máquina: $machineName (RG: $resourceGroupName, Subscription: $subscriptionId)"

    # Definir URI para a API REST
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HybridCompute/machines/$machineName/licenseProfiles/default?api-version=2023-10-03-preview"

    # Criar payload JSON
    $data = @{
        location = $machine.location
        properties = @{
            softwareAssurance = @{
                softwareAssuranceCustomer = $true
            }
        }
    }
    
    $json = $data | ConvertTo-Json -Depth 3

    # Executar chamada REST
    try {
        $response = Invoke-RestMethod -Method PUT -Uri $uri -ContentType "application/json" -Headers $header -Body $json
        Write-Host "✅ Máquina $machineName processada com sucesso!"
        Write-Host "Resposta da API: $($response.properties | ConvertTo-Json -Depth 3)"
    }
    catch {
        Write-Host "⚠️ Erro ao processar a máquina `${machineName}`: $_"
    }
}

Write-Host "`n✅ Script finalizado!"