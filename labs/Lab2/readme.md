# Software Distribution

## 1 - Laboratory Requirements
*Important: Best security practices were not adopted for this scenario.*

- Create a **Storage Account**.
- Enable the **Allow Blob anonymous access** setting.
- Create a **container** with the **Blob - anonymous read access for blobs only** setting.
- Copy the necessary binaries for the lab to this container or use the public link from the 7-Zip provider.
- For this example, the **7-Zip** utility was used, available at [https://www.7-zip.org/](https://www.7-zip.org/).

### Examples for the same file:

### **Windows**
- [7z2409-x64.exe](https://www.7-zip.org/a/7z2409-x64.exe) - Using the provider's repository  
- [7z2408-x64.exe](https://arcboxapps.blob.core.windows.net/apps/7z2408-x64.exe) - Using my Storage Account. **Access may not be available here; this is just an illustrative example. :-)**

### **Linux**
- [custom_script_linux_v1.sh](https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/refs/heads/main/templates/lab2_custom_script_linux_v1.sh) - Using the provider's repository  
- [custom_script_linux_v1.sh](https://arcboxapps.blob.core.windows.net/apps/custom_script_linux_v1.sh) - Using my Storage Account. **Access may not be available here; this is just an illustrative example. :-)**

> **Note:** We can also use **Private Endpoints**, which require additional configurations in the on-premises environment and related adjustments. More details can be found [here](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints).

---

## 2 - Software Distribution

We will use the **Custom Script Extension** for Windows and Linux. More information can be found [here](https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows).

Additional details on extensions can be found in this article: [Managing Extensions](https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions).

Additional references are available [here](https://github.com/microsoft/azure_arc/tree/main/azure_arc_servers_jumpstart/archive/extensions/arm).

> **Uninstalling the Extension:** If you need to uninstall the extension, one method is via command line, as shown in the examples below:  
> [How to Manage Extensions via CLI](https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions-cli)

```azurecli
az connectedmachine extension delete --name CustomScript --resource-group rg-azurearc-itpro-br --machine-name Arcbox-Ubuntu-01 --verbose
az connectedmachine extension delete --name CustomScriptExtension --resource-group rg-azurearc-itpro-br --machine-name ArcBox-Win2k25 --verbose
```

---

## 3 - Examples of Commands for Windows and Linux

### Windows

- **Installation of 7-Zip 24.08**
```azurecli
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\lab2_Windows_CS_Template.json --parameters .\lab2_Windows_CS_ParameteresInstall7zip.json --parameters vmName=ArcBox-Win2k25 --verbose
```

- **Uninstallation of 7-Zip 24.08**
```azurecli
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\lab2_Windows_CS_Template.json --parameters .\lab2_Windows_CS_ParameteresUninstall7zip.json --parameters vmName=ArcBox-Win2k25 --verbose
```

- **Version upgrade from 7-Zip 24.08 to 7-Zip 24.09**
```azurecli
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\lab2_Windows_CS_Template.json --parameters .\lab2_Windows_CS_ParameteresInstall7zip09.json --parameters vmName=ArcBox-Win2k25 --verbose
```

### Linux
- **Installation**
```azurecli
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\lab2_Linux_CS_Template.json --parameters .\lab2_Linux_CS_ParameteresMotdInstall.json --parameters vmName=Arcbox-Ubuntu-01 --verbose
```

- **Uninstallation**
```azurecli
az deployment group create --resource-group rg-azurearc-itpro-br --template-file .\lab2_Linux_CS_Template.json --parameters .\lab2_Linux_CS_ParameteresMotdUninstall.json --parameters vmName=Arcbox-Ubuntu-01 --verbose
```

---

## Consider other usage possibilities such as Run-Command
[Azure Arc Run-Command](https://learn.microsoft.com/en-us/azure/azure-arc/servers/run-command)