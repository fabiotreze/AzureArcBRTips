# Requisitos do Laboratório (Importante ressaltar que, para este cenário, não foram adotadas as boas práticas de segurança.)

1. Criar uma conta de armazenamento (Storage Account).
2. Habilitar a configuração **Allow Blob anonymous access**.
3. Criar um container com a configuração **Blob - anonymous read access for blobs only**.
4. Copiar os binários necessários para o laboratório para este container, ou utilizar o link público do fornecedor do 7-Zip.
5. Para este exemplo, foi utilizado o utilitário 7-Zip, disponível em [https://www.7-zip.org/](https://www.7-zip.org/).

# Exemplos para o mesmo arquivo:

### **Windows**
- [7z2409-x64.exe](https://www.7-zip.org/a/7z2409-x64.exe), utilizando o repositório do fornecedor
- [7z2408-x64.exe](https://arcboxapps.blob.core.windows.net/apps/7z2408-x64.exe), utilizando o meu storage account. **O acesso pode não estar disponível aqui; este é apenas um exemplo ilustrativo. :-)**

### **Linux**
- [custom_script_linux_v1.sh](https://raw.githubusercontent.com/fabiotreze/AzureArcDemo/refs/heads/main/Lab2/custom_script_linux_v1.sh), utilizando o repositório do fornecedor
- [custom_script_linux_v1.sh](https://arcboxapps.blob.core.windows.net/apps/custom_script_linux_v1.sh), utilizando o meu storage account **O acesso pode não estar disponível aqui; este é apenas um exemplo ilustrativo. :-)**

Podemos utilizar também **Private Endpoints**, o que requer configurações adicionais no ambiente on-premise e engarços relacionados. Mais detalhes podem ser encontrados [aqui](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints).

# Distribuição de Software

Para isso, utilizaremos a **Custom Script Extension** para Windows e Linux. Mais informações podem ser encontradas [aqui](https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows).

Detalhes adicionais sobre extensões podem ser encontrados neste artigo: [Gerenciamento de Extensões](https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions).

Referências adicionais estão disponíveis [aqui](https://github.com/microsoft/azure_arc/tree/main/azure_arc_servers_jumpstart/archive/extensions/arm).

Caso precise desinstalar a extensão, um dos métodos é via linha de comando, como nos exemplos abaixo:
[Como Gerenciar Extensões via CLI](https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions-cli)

```bash
az connectedmachine extension delete --name CustomScript --resource-group rg-azurearc-itpro-br --machine-name Arcbox-Ubuntu-01 --verbose
az connectedmachine extension delete --name CustomScriptExtension --resource-group rg-azurearc-itpro-br --machine-name ArcBox-Win2k25 --verbose

# Exemplos de Comandos para Windows e Linux

### Windows

- **Instalação do 7-Zip 24.08**
```bash
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CS_Template.json --parameters .\Windows_CS_ParameteresInstall7zip.json --parameters vmName=ArcBox-Win2k25 --verbose

- **Desinstalação do 7-Zip 24.08**
```bash
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CS_Template.json --parameters .\Windows_CS_ParameteresUninstall7zip.json --parameters vmName=ArcBox-Win2k25 --verbose

- **Atualização de versão do 7-Zip 24.09 para 7-Zip 24.09**
```bash
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Windows_CS_Template.json --parameters .\Windows_CS_ParameteresInstall7zip09.json --parameters vmName=ArcBox-Win2k25 --verbose

### Linux
- **Instalação**
```bash
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Linux_CS_Template.json --parameters .\Linux_CS_ParameteresMotdInstall.json --parameters vmName=Arcbox-Ubuntu-01 --verbose

- **Desinstalação**
```bash
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\Linux_CS_Template.json --parameters .\Linux_CS_ParameteresMotdUninstall.json --parameters vmName=Arcbox-Ubuntu-01 --verbose
```

# Para o futuro
https://learn.microsoft.com/en-us/azure/azure-arc/servers/run-command
