# Azure Arc – Connected Machine Agent Version Compliance (Workbook)

[English](README.md) · [Português](README.pt-BR.md)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-agent-support-azuredeploy.json)

> ⚠️ **Personal, independent project – not an official Microsoft tool.** Provided *as is*, without warranty; see the repository [disclaimer](../../DISCLAIMER.md). Support status is an **estimate** (Azure APIs do not expose release dates) – validate against the [agent release notes](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes). You are responsible for how you use it.

Azure Monitor workbook for Azure Arc-enabled servers. It answers three questions:

1. Are my **Connected Machine agents likely within the support window and above the configured minimum version**?
2. Is **automatic agent upgrade** enabled and working?
3. **What must be fixed**, and on which servers?

Support is estimated from sequential release numbers, not verified release dates; being above the configured minimum is not proof that all security fixes are installed. No version list is hard-coded: the reference is read live from Azure (auto-upgrade target set by Azure, Hybrid Compute catalog APIs, Resource Graph, Advisor, Policy). Bilingual UI (English / Português). Read-only.

## Sections

| # | Section | What it shows |
|---|---|---|
| 1 | Overview | Latest / Supported / Out of support / Unknown / **Below security floor**, connectivity, auto-upgrade |
| 2 | Distribution | Versions, connection status, auto-upgrade health |
| 3 | Azure Advisor | Blockers (expired / disconnected) and agent recommendations, with freshness check |
| 4 | Server inventory | One row per server, below-floor and out-of-support first |
| 5 | Automatic agent upgrade | Eligibility, health (On track / Lagging / Failing / Blocked), last attempt |
| 6 | Latest reference & manual upgrade paths | Latest per OS and its source; next step and download per installed version |
| 7 | Azure Policy | Policy compliance of Arc-enabled servers |
| 8 | Extensions | All extensions: auto-upgrade coverage, versions vs. versions published by Azure, issues grouped by cause |

## Rules (editable in Edit mode)

| Parameter | Default | Meaning |
|---|---|---|
| SupportWindow | 12 releases | Heuristic only: approximates the official last-12-months policy using sequential release numbers; verify release dates in the agent release notes |
| AutoUpgradeTolerance | 1 | Within one release of the reference; *On track* also requires connectivity and no failed last attempt |
| MinAutoUpgradeVersion | 1.57 | Automatic agent upgrade is available from agent 1.57 |
| **SecurityFloorVersion** | **1.61** | Configurable minimum based on previously identified local elevation-of-privilege CVEs (CVE-2025-49692, CVE-2025-26627, CVE-2025-55316, CVE-2026-26117); being at/above it does **not** certify security. Review new security fixes and this threshold regularly |
| LatestOverride | (empty) | Force the latest version when no Azure signal is available |

## Deploy

- **Deploy to Azure** button above → pick subscription / resource group → open in *Azure Monitor → Workbooks*.
- **Azure CLI**: `az deployment group create -g <resource-group> --template-uri https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/main/templates/arc-agent-support-azuredeploy.json`
- **Manual**: Workbooks → New → *Advanced Editor* (`</>`) → paste [`arc-agent-support-workbook.json`](../arc-agent-support-workbook.json) → Apply → Save.

**Permissions:** Reader on the subscriptions / management group to query data. Deploying the ARM template or saving the workbook requires additional permissions to deploy/create or update the workbook resource. Queries are read-only; deployment creates a resource.

## Validation

[`scripts/Test-ArcAgentSupportWorkbook.ps1`](../../scripts/Test-ArcAgentSupportWorkbook.ps1) reads the workbook and runs every query, every filter value, parameter variations and all extension drill-downs, checking 20+ logical invariants (read-only). Requires PowerShell 7+, Az.Accounts and Az.ResourceGraph. Run from the repository root:

```powershell
Connect-AzAccount
./scripts/Test-ArcAgentSupportWorkbook.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Mode Matrix -OutFolder ./wb-test
```

> Test reports contain environment data – treat them as confidential and never attach them to issues.

## Related

- [Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) – point-in-time security assessment; this workbook is the continuous view of the agent/extension part.
- [Manage Azure Connected Machine agent versions](https://learn.microsoft.com/azure/azure-arc/servers/manage-agent) · [Resolve Advisor recommendations for Arc-enabled servers](https://learn.microsoft.com/azure/azure-arc/servers/resolve-azure-advisor-recommendations)

See [CHANGELOG](CHANGELOG.md).
