Distribuição de Software

Opção 1: Custom Script Extension --> referências https://github.com/microsoft/azure_arc/tree/main/azure_arc_servers_jumpstart/archive/extensions/arm
https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows

Garantir que não tenha a extensão, passos para remover a extensão
https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions-cli
az connectedmachine extension delete --name CustomScript --resource-group rg-azurearc-itpro-br --machine-name Arcbox-Ubuntu-01 --verbose
az connectedmachine extension delete --name CustomScriptExtension --resource-group rg-azurearc-itpro-br --machine-name ArcBox-Win2k25 --verbose

Criar storage account e mudar o container para Anonymous access level
* Somente para facilitar a demonstração, não recomendado em ambiente produtivo

Deploy custom Motd Linux
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Linux_CustomScript_Template.json --parameters .\Linux_CustomScript_ParameteresCustomMotd.json --parameters vmName=Arcbox-Ubuntu-01 --verbose

Deploy 7-zip Windows
Install
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CustomScriptExtension_Template.json --parameters .\Windows_CustomScriptExtension_ParameteresInstall7zip.json --parameters vmName=ArcBox-Win2k25 --verbose

Uninstall
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CustomScriptExtension_Template.json --parameters .\Windows_CustomScriptExtension_ParameteresUninstall7zip.json --parameters vmName=ArcBox-Win2k25 --verbose


Deploy Choco and Other Apps
Install
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CustomScriptExtension_Template.json --parameters .\Windows_CustomScriptExtension_ParameteresInstallChocoandOthers.json --parameters vmName=ArcBox-Win2k25 --verbose

https://learn.microsoft.com/en-us/azure/logic-apps/azure-arc-enabled-logic-apps-overview

https://learn.microsoft.com/en-us/azure/azure-arc/servers/run-command