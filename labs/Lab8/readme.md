## Azure Arc - Windows Server Management Enabled by Azure Arc

[Windows Server Management Overview](https://learn.microsoft.com/en-us/azure/azure-arc/servers/windows-server-management-overview?tabs=portal#enrollment)

## Objective  
> Windows Server Management enabled by Azure Arc provides customers with Windows Server licenses that have active Software Assurance or active subscription licenses.

### Purpose

This repository contains the **Azure Arc Windows SA Script**, designed to facilitate the **activation of the Software Assurance Benefit** for Windows machines in scenarios with **an active Software Assurance contract**.

**Why use this script?**  
By default, when onboarding Windows to Azure Arc, the Windows SA Benefit is not enabled automatically.

The script **`lab8_AzureArcWindowsSAScript.ps1`** can be used in a **runbook** and is available in the **scripts** folder of this repository. You can access it directly at the following link:  
[lab8_AzureArcWindowsSAScript.ps1](https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/refs/heads/main/scripts/lab8_AzureArcWindowsSAScript.ps1).  **Recommended**

---

If you prefer to perform the process manually, I have also provided a PowerShell script.

The script **`lab8_AzureArcWindowsSAScriptManual.ps1`** can be used in a **command line** and is available in the **scripts** folder of this repository. You can access it directly at the following link:  
[lab8_AzureArcWindowsSAScriptManual.ps1](https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/refs/heads/main/scripts/lab8_AzureArcWindowsSAScriptManual.ps1).  

---

### Requirements

#### Automation Account
- The **Az.Account** and **Az.ResourceGraph** modules must be installed for the script to function correctly.  
- A **managed identity** must be configured for the Automation Account, enabling secure access to the required resources in Azure.  

#### Runbook
- A **schedule** for the **runbook** must be configured to ensure the script runs automatically at predefined intervals.  

---

### Parameters

The script requires the following parameters:

- **SubscriptionID**: The ID of the Azure subscription where the Azure Arc resources are located.
- **Location**: The Azure region where your Azure Arc resources are deployed.

**What does this solve?**  
Activates the Windows SA benefit for Windows servers with an eligible license, ensuring that an active Software Assurance contract is in place.

---

### Note
Ensure your Automation Account and Azure resources are correctly configured before running the script.

## Keywords for Search  

`#AzureArc #Microsoft #Azure #HybridCompute #HybridCloud #Cloud #Tags #AzureArcSQL #AzureArcBRTips`
