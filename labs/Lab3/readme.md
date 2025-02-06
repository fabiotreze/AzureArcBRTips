# Compliance Management

## Objective  
>Utilize DSC (Desired State Configuration) in conjunction with Azure Arc Guest Configuration (Machine Configuration) to verify the presence of a specific software. If the software is not installed, it will be automatically installed on the Azure Arc-enabled machines.

## 1 - Technical References
It is important to pay attention to the technical requirements of modules for the machine that will be used to create the custom package and Azure Policy usage.

- [Azure Arc JumpStart: Machine Configuration Custom Windows](https://azurearcjumpstart.io/azure_arc_jumpstart/azure_arc_servers/day2/arc_automanage/arc_automanage_machine_configuration_custom_windows) - **Install the modules mentioned in this article on the machine that will be used to create the custom package**

Other links may and should be consulted as additional technical references.
- [Software Installation Using Machine Configuration and Azure Policy](https://techcommunity.microsoft.com/blog/coreinfrastructureandsecurityblog/software-installation-using-machine-configuration-and-azure-policy/3695636)
- [Overview of Machine Configuration in Azure](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/overview)
- [Fix](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/whats-new/agent)

**DSC Usage Examples**
The repository below can be used as a reference for creating new resources, allowing a wide variety of actions with **Guest Configuration** and Azure Arc. It contains various DSC examples that serve as a foundation and inspiration, simplifying the process and avoiding the need to start from scratch.

- [Github PSDscResources](https://github.com/PowerShell/PSDscResources/tree/dev)
- [Azure Policy built-in packages for guest configuration](https://learn.microsoft.com/en-us/azure/governance/policy/samples/built-in-packages)

---

## 2 - Create a Custom Package
[How to set up a machine configuration authoring environment](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/how-to/develop-custom-package/1-set-up-authoring-environment)

---

## 3 - To create the MOF file, refer to the official Microsoft document on how to create a custom package.
Save and run the file [lab3_sample7zip.ps1](https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/refs/heads/main/scripts/lab3_sample7zip.ps1). This will generate the **localhost.mof** file.

## 4 - To create the ZIP file, refer to the official Microsoft document on how to create a custom package and use the previously generated .MOF file.

```powershell
New-GuestConfigurationPackage `
-Name 'Install7zip_MsiPackageFromHttp' `
-Configuration ".\Install7zip_MsiPackageFromHttp/localhost.mof" `
-Type AuditAndSet `
-Path .\ `
-Force
```

This command will generate the necessary package to apply and audit the desired configuration. For testing, copy the **Install7zip_MsiPackageFromHttp.zip** file to a server and validate it using the following command:

```powershell
Start-GuestConfigurationPackageRemediation -Path .\Install7zip_MsiPackageFromHttp.zip
```
---

# 5 - As the next step, we can use this file to create a policy definition in Azure.
[How to create custom computer configuration policy definitions](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/how-to/create-policy-definition)

We can follow the guidelines in the article to store the file in a **Storage Account** and then get the **URI** to use in the following command:

```powershell
$contentUri = "https://arcboxmachineconfigyqvkt.blob.core.windows.net/machineconfiguration/Install7zip_MsiPackageFromHttp.zip" #O acesso pode não estar disponível aqui; este é apenas um exemplo ilustrativo. :-)**
$contentUri

$PolicyConfig      = @{
  PolicyId      = '704dccbb-132a-4eb8-b6a4-409608b5b2ee' #Utilize new-guid no powershell para gerar um novo GUID
  ContentUri    = $contentUri
  DisplayName   = '(ArcBox - Custom) My policy Apply_and_Autocorrect - Install7zip_MsiPackageFromHttp'
  Description   = '(ArcBox - Custom) My policy Apply_and_Autocorrect - Install7zip_MsiPackageFromHttp'
  Path          = './policies/auditIfNotExists.json'
  Platform      = 'Windows'
  PolicyVersion = '1.0.0'
  Mode          = 'ApplyAndAutoCorrect'
}

New-GuestConfigurationPolicy @PolicyConfig -verbose
```
>Reexecute the command below without the **Mode** parameter to generate the two JSON files needed for policy creation. Remember to change **DisplayName** of script.

In your working directory, the directory structure **\policies\auditIfNotExists.json** will be created containing at least two files:

```plaintext
.\Install7zip_MsiPackageFromHttp_AuditIfNotExists.json
.\Install7zip_MsiPackageFromHttp_DeployIfNotExists.json
```

## 6 - Use the previously generated files to create definitions in Azure Policy. Execute the following PowerShell command:

Make sure you are logged in to Azure before executing the commands.

```powershell
New-AzPolicyDefinition -Name '(ArcBox-Custom)-Install7zipMsiPackageFromHttpAuditIfNotExists' -Policy '.\Install7zip_MsiPackageFromHttp_AuditIfNotExists.json' -verbose
New-AzPolicyDefinition -Name '(ArcBox-Custom)-Install7zipMsiPackageFromHttpDeployIfNotExists' -Policy '.\Install7zip_MsiPackageFromHttp_DeployIfNotExists.json' -verbose
```
Após a execução, as definições estarão disponíveis no Azure Policy para avaliação e atribuições.

---

# EXTRA TIP

## 1 - Identify the two important fields: **contentUri** and **contentHash** in the previously generated JSON files.

In the steps mentioned above, JSON files were created that will be used in **Azure Policy**, specifically for creating **Definitions**.

Among these definitions, the **DeployIfNotExists**, stands out, and its structure follows a format similar to the example provided. We have two important fields: **contentUri** and **contentHash**.

```json
"guestConfiguration": {
                "name": "Install7zip_MsiPackageFromHttp",
                "version": "1.0.0",
                "contentType": "Custom",
                "contentUri": "https://arcboxmachineconfigyqvkt.blob.core.windows.net/machineconfiguration/Install7zip_MsiPackageFromHttp.zip",
                "contentHash": "XE5268417B0246DB936CB5C249C8CADF18590F214D399825950A39E381A30491DD"
            }
```

## 2 - We can use this to create the  **Guest Assignments** 
This step will integrate with the **Machine Configuration** functionality along with Azure Arc.

## 3 - How to create an assignment
[Assign a configuration](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/how-to/assign-configuration/overview)

## 4 - A common question may arise: when should I use **Guest Configuration** and when should I use **Azure Policy**?

Remember that the information presented below are just examples and are not limited to what is shown in the table; they can be applied more broadly depending on the scenario.

| **Aspect**                | **Azure Policy**                              | **Guest Configuration (Machine Configuration)** |
|---------------------------|-----------------------------------------------|-------------------------------------------------|
| **Scope**                 | Infrastructure and resources                  | Operating System (Guest OS)                     |
| **Enabling**              | Rules for managed resources                   | VM Extension or Azure Arc                      |
| **Granularity**           | Macro (resources, regions, tags)              | Micro (OS, services, files)                    |
| **Use Cases**             | Location restrictions, SKUs, tags             | SSH configurations, services, files            |
| **Azure Arc Compatibility** | Yes                                         | Yes                                             |
| **Auto Remediation**      | Limited (applies to infrastructure)           | Yes (applies to OS configuration)              |

## Keywords for Search  

`#AzureArc #Microsoft #Azure #HybridCompute #HybridCloud #Cloud #AzureMonitor #Automation #DSC #PowerShell #MachineConfiguration #GuestConfiguration #AzureArcBRTips`