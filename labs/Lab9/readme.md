# Using Azure Automation Account to Operate Azure Arc–enabled SQL Server with Least Privilege

> **Note**  
> This document and script were created based on the official Microsoft guidance:  
> [Configure least privilege for Azure Arc–enabled SQL Server](https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/configure-least-privilege?view=sql-server-ver17).

## Overview

This repository contains a PowerShell Runbook that automates the activation of the **LeastPrivilege FeatureFlag** on Azure Arc SQL-enabled machines. It uses Azure Resource Graph to identify machines where the flag is missing or disabled and applies the change using Azure CLI.

This improves security posture and ensures consistent configuration across hybrid environments.

## Getting Started

The script is designed to run in an **Azure Automation Account** with **Managed Identity** enabled. It queries all subscriptions accessible to the identity, identifies eligible machines, and enables the LeastPrivilege flag.

### Why Use This Script?

By default, some Azure Arc SQL machines may not have the LeastPrivilege FeatureFlag enabled, which can lead to elevated permissions and inconsistent configurations. This script ensures the flag is applied consistently across all connected machines.

## Deploying Artifacts

The script **`Lab9_RunBook_ArcSQLEnableLeastPrivilege.ps1`** is part of this repository and can be imported into an Azure Automation Runbook.

You can access it directly at the following link:  
[Lab9_RunBook_ArcSQLEnableLeastPrivilege.ps1](https://github.com/fabiotreze/AzureArcBRTips/blob/main/scripts/Lab9_RunBook_ArcSQLEnableLeastPrivilege.ps1)

## Prerequisites

### Automation Account

- PowerShell Runtime version **7.2 or higher**
- Modules:
  - `Az.Accounts` version **2.7.5 or higher**
  - `Az.ResourceGraph`
- **Azure CLI** must be available in the environment
- **Managed Identity** must be enabled and assigned permissions to:
  - Read and modify Azure Arc machines
  - Query Resource Graph

### Permissions

The Managed Identity must have the following roles assigned:
- **Reader** or **Contributor** on target subscriptions
- **Hybrid Compute Administrator** (or equivalent) to modify Azure Arc machine extensions

## What the Script Does

- Authenticates using Managed Identity (PowerShell and Azure CLI)
- Validates environment and required modules
- Ensures the `arcdata` CLI extension is installed
- Queries Azure Resource Graph for SQL-enabled Azure Arc machines
- Identifies machines missing or with disabled LeastPrivilege FeatureFlag
- Enables the flag using Azure CLI
- Logs results in structured format (CSV-style)

## Example Execution Output

Below is a sample output from the Runbook execution. It demonstrates the structured logging format and the result of enabling the LeastPrivilege FeatureFlag on Azure Arc SQL-enabled machines:

```powershell
[2025-09-19 12:57:56][INFO] Environment successfully validated.

[2025-09-19 12:57:56][INFO] Authenticating to Azure using managed identity (PowerShell)...

[2025-09-19 12:57:59][INFO] Authenticating to Azure CLI using managed identity...

[2025-09-19 12:58:15][INFO] Authentication completed successfully.

[2025-09-19 12:58:16][INFO] Installing 'arcdata' extension...

[2025-09-19 12:58:45][INFO] 'arcdata' extension installed successfully.

[2025-09-19 12:58:46][INFO] Setting context for subscription: ME-MngEnvMCAP385546-farodrig-1 (c0d36e7b-027e-4956-94bf-6e17dbf5e791)

[2025-09-19 12:58:46][INFO] Querying machines in subscription c0d36e7b-027e-4956-94bf-6e17dbf5e791...

[2025-09-19 12:58:47][INFO] Processing machine: app01 in resource group rg-azurearc-itpro-br...

[2025-09-19 12:58:56][RESULT] "app01","rg-azurearc-itpro-br","c0d36e7b-027e-4956-94bf-6e17dbf5e791","leastprivilege","false","true","connected","9/19/2025 11:49:37 AM","Success"

[2025-09-19 12:58:57][INFO] Processing machine: arcbox-win2k12 in resource group rg-azurearc-itpro-br...

[2025-09-19 12:59:02][RESULT] "arcbox-win2k12","rg-azurearc-itpro-br","c0d36e7b-027e-4956-94bf-6e17dbf5e791","","","true","connected","9/19/2025 11:59:30 AM","Success"

[2025-09-19 12:59:02][INFO] Processing machine: arcbox-win2k22 in resource group rg-azurearc-itpro-br...

[2025-09-19 12:59:06][RESULT] "arcbox-win2k22","rg-azurearc-itpro-br","c0d36e7b-027e-4956-94bf-6e17dbf5e791","","","true","connected","9/19/2025 12:01:05 PM","Success"

[2025-09-19 12:59:06][INFO] Processing machine: arcbox-win2k25 in resource group rg-azurearc-itpro-br...

[2025-09-19 12:59:11][RESULT] "arcbox-win2k25","rg-azurearc-itpro-br","c0d36e7b-027e-4956-94bf-6e17dbf5e791","","","true","connected","9/19/2025 12:00:16 PM","Success"

[2025-09-19 12:59:12][INFO] Processing machine: sccm in resource group rg-azurearc-itpro-br...

[2025-09-19 12:59:16][RESULT] "sccm","rg-azurearc-itpro-br","c0d36e7b-027e-4956-94bf-6e17dbf5e791","leastprivilege","false","true","connected","9/19/2025 11:17:04 AM","Success"

[2025-09-19 12:59:16][INFO] Setting context for subscription: ME-MngEnvMCAP385546-farodrig-2 (8e467ebb-7651-4c72-86ec-32f0e7359355)

[2025-09-19 12:59:16][INFO] Querying machines in subscription 8e467ebb-7651-4c72-86ec-32f0e7359355...

[2025-09-19 12:59:16][INFO] Processing machine: sql22-01 in resource group rg-azurearc-local-eus...

[2025-09-19 12:59:18][RESULT] "sql22-01","rg-azurearc-local-eus","8e467ebb-7651-4c72-86ec-32f0e7359355","leastprivilege","false","true","connected","9/19/2025 11:10:46 AM","Success"

[2025-09-19 12:59:19][INFO] Execution completed successfully.
```
