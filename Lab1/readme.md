# Usaremos o Azure Arc JumpStart para Criar o Ambiente de Demonstração
[Azure Arc JumpStart ITPro](https://azurearcjumpstart.com/azure_jumpstart_arcbox/ITPro)

## 1 - Alterações no Arquivo `main.bicep`
O arquivo em `azure_arc\azure_jumpstart_arcbox\bicep` foi modificado com os seguintes parâmetros, que são exemplos de configuração.

**Exemplo de Parâmetros no arquivo `main.bicepparam`:**

```bicep
using 'main.bicep'

param tenantId = '0d994b7c-f5b1-5b99-bffc-82f61f963c54'
param windowsAdminUsername = 'arcdemo'
param windowsAdminPassword = 'ArcPassword123!!'
param logAnalyticsWorkspaceName = 'log-AzureArcBankDemo'
param flavor = 'ITPro'
param deployBastion = false
param vmAutologon = true
```

## 2 - Comando de exemplo para implementar a solução:
```azurecli
az deployment group create -g "rg-azurearc-itpro-br" -f "main.bicep" -p "main.bicepparam" --verbose
``` 