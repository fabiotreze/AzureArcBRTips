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
- **Azure CLI** (pre-installed in Azure Automation sandbox — version 2.56.0+)
- No Az PowerShell modules required — the script uses **100% Azure CLI**
- CLI extensions `resource-graph` and `arcdata` are auto-installed by the script
- **Managed Identity** must be enabled on the Automation Account

### Permissions

The Managed Identity must have the following **Azure role assignments** on each target subscription:

| Role | Purpose |
|---|---|
| **Reader** | List subscriptions, query Azure Resource Graph |
| **Azure Connected Machine Resource Administrator** | Read/write Azure Arc machines and extensions (includes FeatureFlag changes) |

> **Note**: Both roles must be assigned on **every subscription** that the script will process.

## What the Script Does

- Authenticates using Managed Identity (`az login --identity`)
- Validates Azure CLI availability
- Auto-installs CLI extensions (`resource-graph`, `arcdata`)
- Iterates all enabled subscriptions
- Queries Azure Resource Graph (KQL) for connected Arc machines with `WindowsAgent.SqlServer` where LeastPrivilege is disabled or missing
- Enables the flag using `az sql server-arc extension feature-flag set`
- Includes retry logic (2 attempts with 10s delay)
- Paginates Resource Graph results (supports >1000 machines per subscription)
- Logs results in structured format (CSV-style) with per-subscription and global summary

## Important: Local Service Accounts on Target Machines

Before enabling the LeastPrivilege FeatureFlag, ensure that the target machines meet the local service account requirements:

| Service | Account | Purpose |
|---|---|---|
| Azure Connected Machine Agent | `NT SERVICE\himds` | Low-privileged virtual account for the Azure Hybrid Instance Metadata Service. Must have the **Log on as a service** right. See [Azure Arc prerequisites](https://docs.azure.cn/en-us/azure-arc/servers/prerequisites#local-user-logon-right-for-windows-systems). |
| SQL Server Extension Agent | `NT SERVICE\SqlServerExtension` | Local Windows service account used when Least Privilege mode is enabled. Replaces the default `Local System` context with a dedicated low-privileged identity. See [Operate SQL Server enabled by Azure Arc with least privilege](https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/configure-least-privilege?view=sql-server-ver17). |

> **Warning**: After enabling the LeastPrivilege FeatureFlag, the SQL Server Extension Agent service will switch from `Local System` to `NT SERVICE\SqlServerExtension`. Verify that:
> - The `NT SERVICE\SqlServerExtension` account has the **Log on as a service** right on the target machine.
> - The account has proper access to SQL Server instances (the extension manages this automatically during the `asyncEnable` process).
> - On older OS versions (e.g., Windows Server 2012 R2), WMI-related errors may appear in logs but do not block functionality.

## Example Execution Output

Below is a sample output from the Runbook execution. It demonstrates the structured logging format and the result of enabling the LeastPrivilege FeatureFlag on Azure Arc SQL-enabled machines:

```
[2026-03-05 21:46:37][INFO] === Azure Arc SQL LeastPrivilege Runbook ===

[2026-03-05 21:46:50][INFO] Azure CLI 2.56.0 | PowerShell 7.2.0

[2026-03-05 21:46:50][INFO] Authenticating with managed identity...

[2026-03-05 21:46:53][INFO] Authenticated.

[2026-03-05 21:46:54][INFO] Installing extension 'resource-graph'...

[2026-03-05 21:47:03][INFO] Installing extension 'arcdata'...

[2026-03-05 21:47:51][INFO] Found 2 enabled subscription(s).

[2026-03-05 21:47:51][RESULT] MachineName,ResourceGroup,SubscriptionId,LPStatusBefore,UpdateResult

[2026-03-05 21:47:52][INFO] --- Subscription: ME-MngEnvMCAP385546-farodrig-2 (8e467ebb-7651-4c72-86ec-32f0e7359355)

[2026-03-05 21:47:57][INFO] All machines compliant (or none exist).

[2026-03-05 21:47:57][INFO] --- Subscription: ME-MngEnvMCAP385546-farodrig-1 (c0d36e7b-027e-4956-94bf-6e17dbf5e791)

[2026-03-05 21:48:01][INFO] Found 3 non-compliant machine(s).

[2026-03-05 21:48:01][INFO]   -> sccm | RG: rg-azurearc-itpro-br | LP: false

[2026-03-05 21:48:07][RESULT] sccm,rg-azurearc-itpro-br,c0d36e7b-027e-4956-94bf-6e17dbf5e791,false,Success

[2026-03-05 21:48:07][INFO]   -> sql22-01 | RG: rg-azurearc-itpro-eus2-new | LP: false

[2026-03-05 21:48:11][RESULT] sql22-01,rg-azurearc-itpro-eus2-new,c0d36e7b-027e-4956-94bf-6e17dbf5e791,false,Success

[2026-03-05 21:48:11][INFO]   -> arcbox-sql | RG: rg-azurearc-itpro-eus2 | LP: false

[2026-03-05 21:48:16][RESULT] arcbox-sql,rg-azurearc-itpro-eus2,c0d36e7b-027e-4956-94bf-6e17dbf5e791,false,Success

[2026-03-05 21:48:16][INFO] === SUMMARY ===

[2026-03-05 21:48:16][INFO] Subscriptions: 2 total | 1 with non-compliant machines | 1 fully compliant | 0 skipped

[2026-03-05 21:48:16][INFO] Machines: 3 processed | 3 success | 0 failure

[2026-03-05 21:48:16][INFO] === Done ===
```
