# Azure Arc – Connected Machine Agent Version Compliance (Workbook)

[English](README.md) · [Português](README.pt-BR.md)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-agent-support-azuredeploy.json)

> ⚠️ **Personal, independent project – not an official Microsoft tool.** Provided *as is*, without warranty; see the repository [disclaimer](../../DISCLAIMER.md). Support status is an **estimate** (Azure APIs do not expose release dates) – validate against the [agent release notes](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes). You are responsible for how you use it.

Azure Monitor workbook for Azure Arc-enabled servers. **Current version: 4.6.8** (see the [CHANGELOG](CHANGELOG.md)). It answers three questions:

1. Are my **Connected Machine agents likely within the support window and above the configured minimum version**?
2. Is **automatic agent upgrade** enabled and working?
3. **What must be fixed**, and on which servers?

Support is estimated from sequential release numbers, not verified release dates; being above the configured minimum is not proof that all security fixes are installed. No version list is hard-coded: the reference is read live from Azure (auto-upgrade target set by Azure, Hybrid Compute catalog APIs, Resource Graph, Advisor, Policy). The catalog list API is non-deterministic, so the workbook merges several calls, never relies on it alone, and gets downloads by exact version. Bilingual UI (English / Português). Read-only.

## Sections

| # | Section | What it shows |
|---|---|---|
| 1 | Overview | Banner when servers are disconnected / expired; *Fleet status* and *Version & upgrade* tiles (Latest / Supported / Out of support / **Below security floor** / auto-upgrade); **Servers that need action** with the reason |
| 2 | Distribution | Versions, connection status, auto-upgrade health (charts are optional: *Show distribution charts*, off by default) |
| 3 | Azure Advisor | Blockers (expired / disconnected) and agent recommendations, with a link to the impacted resources in Advisor and a freshness check |
| 4 | Server inventory | One row per server (up to 1000), below-floor and out-of-support first |
| 5 | Automatic agent upgrade | Eligibility (agent 1.67+), health (On track / Lagging / Failing / Blocked), last attempt |
| 6 | Latest reference & manual upgrade paths | Latest per OS and its source; next step per installed version; agent download by exact version (latest pre-selected) |
| 7 | Azure Policy | Only agent / automatic-upgrade policies, with an explicit message when none is assigned |
| 8 | Extensions | All extensions: auto-upgrade coverage, versions vs. versions published by Azure, issues grouped by cause with every affected server |

Controls: *Show guide* adds the legend, methodology and official sources. *Show changelog* (Edit mode) shows the editorial history inside the workbook.

## Rules (editable in Edit mode)

| Parameter | Default | Meaning |
|---|---|---|
| SupportWindow | 12 releases | Heuristic only: approximates the official last-12-months policy using sequential release numbers; verify release dates in the agent release notes |
| AutoUpgradeTolerance | 1 | Heuristic, not a documented guarantee (Microsoft rolls automatic upgrades out in batches and retries failures); *On track* also requires connectivity and no failed last attempt |
| MinAutoUpgradeVersion | 1.67 | Automatic agent upgrade requires agent 1.67 or later (Windows: PowerShell execution policy RemoteSigned; Linux: cron service) |
| **SecurityFloorVersion** | **1.61** | Configurable minimum based on public CVE records (CVE-2026-26117 affects agents < 1.61, CVE-2025-49692 < 1.49; CVE-2025-26627 and CVE-2025-55316 as in Arc Posture Review); applied to every OS; being at/above it does **not** certify security. Review new security fixes and this threshold regularly |
| LatestOverride | 1.69 | Manual reference taken from the agent release notes. When filled it takes priority over every other source (it is not a maximum), even if Azure reports a higher version: update or clear it after each release |

Without an override, *Latest* is the highest version Azure reports and can lag the newest release.

## Deploy

- **Deploy to Azure** button above → pick subscription / resource group → open in *Azure Monitor → Workbooks*.
- **Azure CLI**: `az deployment group create -g <resource-group> --template-uri https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/main/templates/arc-agent-support-azuredeploy.json`
- **Manual**: Workbooks → New → *Advanced Editor* (`</>`) → paste [`arc-agent-support-workbook.json`](../arc-agent-support-workbook.json) → Apply → Save.

**Permissions:** Reader on the subscriptions / management group to query data. Deploying the ARM template or saving the workbook requires additional permissions to deploy/create or update the workbook resource. Queries are read-only; deployment creates a resource.

## Validation

[`scripts/Test-ArcWorkbookQueries.ps1`](../../scripts/Test-ArcWorkbookQueries.ps1) reads the workbook, resolves its parameters the way the portal does and runs every query of every tab against your tenant (read-only). It reports status, rows, duration, HTTP 429 throttling and truncation per query. Requires PowerShell 7+, Az.Accounts, Az.ResourceGraph and Reader on the subscriptions. Run from the repository root:

```powershell
Connect-AzAccount -Tenant <tenant-id>
# offline lint (no Azure call)
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -DryRun
# every filter value one at a time + the first 3 extension drill-downs
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Language EN -FilterCombos OneFactor -ExtensionDrill 3
# open each tab like the portal (all its queries at once) with the optional charts on – reproduces HTTP 429
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Burst -SetParam @{ ShowCharts = 'Yes' }
```

Results go to `./workbook-test-results` (excluded by `.gitignore`). With the charts on, the Overview tab runs 10 Resource Graph queries at once; the script retries an occasional HTTP 429 automatically.

`-SetParam` values take effect before dependent parameters are resolved. Query failures, unresolved tokens and parameter failures produce exit code **1**; success produces **0**. Parameter failures appear in the CSV and the red final summary. Run the offline mock regression tests with `pwsh -NoProfile -File .\scripts\Test-ArcWorkbookQueries.Tests.ps1`.

During normal execution, parameters awaiting only values exported by query row selection are reported as **Skipped (aguarda seleção)** in the CSV and summary, without failing the run. Export names are discovered from query metadata. `-ExtensionDrill` supplies selection values and validates the parameter queries; a real failure or an unresolved non-selection token still produces exit code **1**.

> Test reports contain environment data – treat them as confidential and never attach them to issues or commits.

## Related

- [Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) – point-in-time security assessment; this workbook is the continuous view of the agent/extension part.
- [Manage Azure Connected Machine agent versions](https://learn.microsoft.com/azure/azure-arc/servers/manage-agent) · [Resolve Advisor recommendations for Arc-enabled servers](https://learn.microsoft.com/azure/azure-arc/servers/resolve-azure-advisor-recommendations)

See [CHANGELOG](CHANGELOG.md).
