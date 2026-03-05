# Using Azure Automation Account to Activate Software Assurance Benefits on Azure Arc Windows Servers

> **Note**
> This document and script were created based on the official Microsoft guidance:
> [Windows Server Management enabled by Azure Arc](https://learn.microsoft.com/en-us/azure/azure-arc/servers/windows-server-management-overview?tabs=portal#enrollment) |
> [Billing and Extended Security Updates](https://learn.microsoft.com/en-us/azure/azure-arc/servers/billing-extended-security-updates).

## Overview

This repository contains a PowerShell Runbook that automates the **activation of Software Assurance benefits** on Azure Arc Windows Server machines. It uses Azure Resource Graph to identify eligible machines where the benefit is not activated and enables it via REST API.

This ensures that Windows Servers with active Software Assurance contracts have their benefits consistently applied across hybrid environments.

## Getting Started

The script is designed to run in an **Azure Automation Account** with **Managed Identity** enabled. It queries all subscriptions accessible to the identity, identifies eligible machines (connected, licensed, Windows Server), and activates the Software Assurance benefit.

### Why Use This Script?

By default, when onboarding Windows Server to Azure Arc, the Software Assurance benefit is **not enabled automatically**. This script ensures the benefit is applied consistently across all eligible connected machines — no manual intervention required.

## Deploying Artifacts

The script **`lab8_AzureArcWindowsSAScript.ps1`** is part of this repository and can be imported into an Azure Automation Runbook.

You can access it directly at the following link:
[lab8_AzureArcWindowsSAScript.ps1](https://github.com/fabiotreze/AzureArcBRTips/blob/main/scripts/lab8_AzureArcWindowsSAScript.ps1)

## Prerequisites

### Automation Account

- PowerShell Runtime version **7.2 or higher**
- **Azure CLI** (pre-installed in Azure Automation sandbox — version 2.56.0+)
- No Az PowerShell modules required — the script uses **100% Azure CLI**
- CLI extension `resource-graph` is auto-installed by the script
- **Managed Identity** must be enabled on the Automation Account

### Permissions

The Managed Identity must have the following **Azure role assignments** on each target subscription:

| Role | Purpose |
|---|---|
| **Reader** | List subscriptions, query Azure Resource Graph |
| **Azure Connected Machine Resource Administrator** | Read/write Azure Arc machines and license profiles |

> **Note**: Both roles must be assigned on **every subscription** that the script will process.

## What the Script Does

- Authenticates using Managed Identity (`az login --identity`)
- Validates Azure CLI availability
- Auto-installs CLI extension (`resource-graph`)
- Iterates all enabled subscriptions — no parameters required
- Queries Azure Resource Graph (KQL) for **eligible** Windows Server Arc machines where Software Assurance is not activated
  - **Eligible** = `Connected` + `Licensed` + Windows Server OS (excludes client SKUs)
  - Excludes machines already `Activated` or `Activated via Pay-as-you-go`
  - Excludes `Not eligible` machines (disconnected, expired, or not licensed)
- Enables the benefit using `az rest --method PUT` on the `licenseProfiles/default` REST API
- Includes retry logic (2 attempts with 10s delay)
- Paginates Resource Graph results (supports >1000 machines per subscription)
- Logs results in structured format (CSV-style) with per-subscription and global summary

## Example Execution Output

Below is a sample output from the Runbook execution:

```
[2026-03-05 22:45:35][INFO] === Azure Arc Software Assurance Activation Runbook ===

[2026-03-05 22:45:46][INFO] Azure CLI 2.56.0 | PowerShell 7.2.0

[2026-03-05 22:45:46][INFO] Authenticating with managed identity...

[2026-03-05 22:45:48][INFO] Authenticated.

[2026-03-05 22:45:49][INFO] Installing extension 'resource-graph'...

[2026-03-05 22:46:01][INFO] Found 2 enabled subscription(s).

[2026-03-05 22:46:02][RESULT] MachineName,ResourceGroup,SubscriptionId,OperatingSystem,Location,UpdateResult

[2026-03-05 22:46:02][INFO] --- Subscription: ME-MngEnvMCAP385546-farodrig-2 (8e467ebb-7651-4c72-86ec-32f0e7359355)

[2026-03-05 22:46:06][INFO] All machines activated (or none exist).

[2026-03-05 22:46:06][INFO] --- Subscription: ME-MngEnvMCAP385546-farodrig-1 (c0d36e7b-027e-4956-94bf-6e17dbf5e791)

[2026-03-05 22:46:09][INFO] Found 4 machine(s) without Software Assurance benefits.

[2026-03-05 22:46:09][INFO]   -> ArcBox-SQL | RG: rg-azurearc-itpro-eus2 | OS: Windows Server 2022 Standard | Location: eastus2

[2026-03-05 22:46:11][RESULT] ArcBox-SQL,rg-azurearc-itpro-eus2,c0d36e7b-027e-4956-94bf-6e17dbf5e791,Windows Server 2022 Standard,eastus2,Success

[2026-03-05 22:46:11][INFO]   -> ArcBox-Win2K12 | RG: rg-azurearc-itpro-br | OS: Windows Server 2012 R2 Datacenter | Location: brazilsouth

[2026-03-05 22:46:12][RESULT] ArcBox-Win2K12,rg-azurearc-itpro-br,c0d36e7b-027e-4956-94bf-6e17dbf5e791,Windows Server 2012 R2 Datacenter,brazilsouth,Success

[2026-03-05 22:46:13][INFO]   -> ArcBox-Win2K19 | RG: rg-azurearc-itpro-br | OS: Windows Server 2019 Standard | Location: brazilsouth

[2026-03-05 22:46:14][RESULT] ArcBox-Win2K19,rg-azurearc-itpro-br,c0d36e7b-027e-4956-94bf-6e17dbf5e791,Windows Server 2019 Standard,brazilsouth,Success

[2026-03-05 22:46:14][INFO]   -> DC25-01 | RG: rg-azurearc-itpro-eus2-new | OS: Windows Server 2025 Datacenter | Location: eastus2

[2026-03-05 22:46:16][RESULT] DC25-01,rg-azurearc-itpro-eus2-new,c0d36e7b-027e-4956-94bf-6e17dbf5e791,Windows Server 2025 Datacenter,eastus2,Success

[2026-03-05 22:46:17][INFO] === SUMMARY ===

[2026-03-05 22:46:17][INFO] Subscriptions: 2 total | 1 with non-activated machines | 1 fully activated | 0 skipped

[2026-03-05 22:46:17][INFO] Machines: 4 processed | 4 success | 0 failure

[2026-03-05 22:46:17][INFO] === Done ===
```

## Keywords for Search

`#AzureArc #Microsoft #Azure #HybridCompute #HybridCloud #Cloud #SoftwareAssurance #WindowsServer #AzureArcBRTips`
