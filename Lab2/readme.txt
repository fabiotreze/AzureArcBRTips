Requisitos do Laboratório (Importante ressaltar que, para este cenário, não foram adotadas as boas práticas de segurança.)

1 - Criar uma conta de armazenamento (Storage Account).
2 - Habilitar a configuração Allow Blob anonymous access.
3 - Criar um container com a configuração Blob - anonymous read access for blobs only.
4 - Copiar os binários necessários para o laboratório para este container, ou utilizar o link público do fornecedor do 7-Zip.
5 - Para este exemplo, foi utilizado o utilitário 7-Zip, disponível em https://www.7-zip.org/.

Exemplos para o mesmo arquivo:

Windows
https://www.7-zip.org/a/7z2409-x64.exe, utilizando o repositório do fornecedor
https://arcboxapps.blob.core.windows.net/apps/7z2408-x64.exe, utilizando o meu storage account

Linux
https://raw.githubusercontent.com/fabiotreze/AzureArcDemo/refs/heads/main/Lab2/custom_script_linux_v1.sh, utilizando o repositório do fornecedor
https://arcboxapps.blob.core.windows.net/apps/custom_script_linux_v1.sh, utilizando o meu storage account

Podemos utilizar também Private Endpoints, isso irá requerer configurações adicionais no ambiente onpremise e engarcos relacionados
https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints

************************************************************************************************************************************

Distribuição de software, para isso utilizaremos a Custom Script Extension para Windows e Linux https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows
Mais detalhes de extensões pode ser encontrado neste artigo: https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions

Referências adicionais em: https://github.com/microsoft/azure_arc/tree/main/azure_arc_servers_jumpstart/archive/extensions/arm

Caso precise desinstalar a extensão, um dos métodos é via linha de comando como nos exemplos abaixo:
https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions-cli
az connectedmachine extension delete --name CustomScript --resource-group rg-azurearc-itpro-br --machine-name Arcbox-Ubuntu-01 --verbose
az connectedmachine extension delete --name CustomScriptExtension --resource-group rg-azurearc-itpro-br --machine-name ArcBox-Win2k25 --verbose

************************************************************************************************************************************

Windows
- Instalação do 7-Zip 24.08
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CS_Template.json --parameters .\Windows_CS_ParameteresInstall7zip.json --parameters vmName=ArcBox-Win2k25 --verbose

- Desinstalação do 7-Zip 24.08
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CS_Template.json --parameters .\Windows_CS_ParameteresUninstall7zip.json --parameters vmName=ArcBox-Win2k25 --verbose

- Atualização de versão do 7-Zip 24.09 para 7-Zip 24.09
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CS_Template.json --parameters .\Windows_CS_ParameteresInstall7zip09.json --parameters vmName=ArcBox-Win2k25 --verbose

************************************************************************************************************************************

Linux
- Install
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Linux_CS_Template.json --parameters .\Linux_CS_ParameteresMotdInstall.json --parameters vmName=Arcbox-Ubuntu-01 --verbose

- Uninstall
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Linux_CS_Template.json --parameters .\Linux_CS_ParameteresMotdUninstall.json --parameters vmName=Arcbox-Ubuntu-01 --verbose

https://learn.microsoft.com/en-us/azure/azure-arc/servers/run-command