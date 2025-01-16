Requisitos do Laboratório (É importante destacar que, para este cenário, não foram consideradas as boas práticas de segurança.)
1 - Criar uma storage account
2 - Habilitar a configuração Allow Blob anonymous access
3 - Criar um container (Blob - anonymous read access for blobs only)
4 - Copiar os binários necessários para o Laboratório
5 - Para esse exemplo utilizei o utilitário 7-zip que pode ser encontrado em https://www.7-zip.org/

Distribuição de software, para isso utilizaremos a Custom Script Extension para Windows e Linux https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows
Mais detalhes de extensões pode ser encontrado neste artigo: https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions

Referências adicionais em: https://github.com/microsoft/azure_arc/tree/main/azure_arc_servers_jumpstart/archive/extensions/arm

Caso precise desinstalar a extensão, um dos métodos é via linha de comando como nos exemplos abaixo:
https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions-cli
az connectedmachine extension delete --name CustomScript --resource-group rg-azurearc-itpro-br --machine-name Arcbox-Ubuntu-01 --verbose
az connectedmachine extension delete --name CustomScriptExtension --resource-group rg-azurearc-itpro-br --machine-name ArcBox-Win2k25 --verbose

Windows
- Instalação do 7-Zip

- Desinstalação do 7-Zip

- Atualização de versão do 7-Zip




Deploy custom Motd Linux
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Linux_CS_Template.json --parameters .\Linux_CS_ParameteresMotd.json --parameters vmName=Arcbox-Ubuntu-01 --verbose

Deploy 7-zip Windows
Install
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CS_Template.json --parameters .\Windows_CS_ParameteresInstall7zip.json --parameters vmName=ArcBox-Win2k25 --verbose

Uninstall
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CS_Template.json --parameters .\Windows_CS_ParameteresUninstall7zip.json --parameters vmName=ArcBox-Win2k25 --verbose

https://learn.microsoft.com/en-us/azure/azure-arc/servers/run-command