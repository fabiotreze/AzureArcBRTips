# Demo Environment
[Azure Arc JumpStart ITPro](https://azurearcjumpstart.com/azure_jumpstart_arcbox/ITPro)

## 1 - Changes in the `main.bicep` File
The file located in `azure_arc\azure_jumpstart_arcbox\bicep` has been modified with the following parameters, which are configuration examples.

**Example Parameters in the `main.bicepparam` File:**

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

## 2 - Example command to deploy the solution
```azurecli
az deployment group create -g "rg-azurearc-itpro-br" -f "main.bicep" -p "main.bicepparam" --verbose
``` 