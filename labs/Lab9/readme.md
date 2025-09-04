## Azure Arc – Agent Upgrade Monitoring via Logic App

![Azure Arc Agent Upgrade Monitoring](https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/refs/heads/main/images/lab9_AzureArcAgentUpgradeMonitoring.png) Azure Arc-enabled machines that have the `agentUpgrade.enableAutomaticUpgrade` property set to **false**, indicating that automatic agent upgrades are disabled. It runs on a weekly schedule and sends an HTML report via email to a designated recipient.

The Logic App definition **`lab9_AzureArcAgentUpgradeMonitoring.json`** can be used in an **automation workflow** and is available in the **templates** folder of this repository. You can access it directly at the following link:  
https://github.com/fabiotreze/AzureArcBRTips/blob/main/templates/lab9_AzureArcAgentUpgradeMonitoring.json.  **Recommended**

## Objective

Ensure visibility into Azure Arc machines that are not configured for automatic agent upgrades, helping maintain compliance, security, and operational efficiency.

## Purpose

This Logic App automates the detection and reporting of Azure Arc machines with disabled automatic upgrades. It queries the Azure Resource Graph, builds a detailed HTML report, and sends it via email.

## Why use this Logic App?

By default, Azure Arc machines may not have automatic agent upgrades enabled. This Logic App helps identify such machines and provides direct links to their Azure Portal pages for quick remediation.

## What does this Logic App do?

- Queries Azure Resource Graph for machines of type `Microsoft.HybridCompute/machines` with `agentUpgrade.enableAutomaticUpgrade = false`.
- Builds an HTML table with:
  - Machine name
  - Resource group
  - Subscription name
  - Direct link to the Azure Portal resource
- Sends the report via email to the configured recipient (`youremail@yourcompany.com`).

## RBAC Required

- **Managed Identity** must be enabled for the Logic App.
- Permissions required:
  - Reader access to subscriptions
  - Access to Resource Graph

## Requirements

- Azure Logic App
- Managed Identity configured
- Connection to Office 365 (via `office365-1`)
- Email recipient variable (`SendAlertTo`)
- Resource Graph query embedded in the workflow

## Schedule

- **Frequency:** Weekly
- **Time Zone:** E. South America Standard Time

## Parameters

The Logic App uses the following parameters:

- `IncludedSubscriptions`: Optional list of subscriptions to include
- `ExcludedSubscriptions`: Optional list of subscriptions to exclude
- `SendAlertTo`: Email address to receive the report
- `SetEmailSubject`: Subject line for the email
- `resourcesTable`: Resource Graph query string

## What does this solve?

It provides a proactive mechanism to monitor Azure Arc agent upgrade settings, ensuring that machines remain up-to-date and secure.

## Note

Before deploying this Logic App, ensure that:
- The Office 365 connection is correctly configured.
- The Managed Identity has appropriate access.
- The recipient email address is valid.

## Keywords for Search

#AzureArc #Microsoft #Azure #HybridCompute #HybridCloud #Cloud #AgentUpgrade #Automation #LogicApp #ResourceGraph #Compliance #Security