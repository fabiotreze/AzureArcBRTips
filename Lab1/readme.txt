Usaremos o Azure Arc JumpStart para criar o ambiente de demonstração para o Banco.
https://azurearcjumpstart.com/azure_jumpstart_arcbox/ITPro

Alteramos o arquivo em azure_arc\azure_jumpstart_arcbox\bicep com os parâmetros abaixo, que são apenas exemplos.
Main.bicepparam

using 'main.bicep'
param tenantId = 'd4dc091b-7813-4238-bd15-a0cff81d508d'
param windowsAdminUsername = 'arcdemo'
param windowsAdminPassword = 'ArcPassword123!!'
param logAnalyticsWorkspaceName = 'log-AzureArcBankDemo'
param flavor = 'ITPro'
param deployBastion = false
param vmAutologon = true

Comando de exemplo para implementar a solução:
az deployment group create -g "rg-azurearc-itpro-br" -f "main.bicep" -p "main.bicepparam" --verbose