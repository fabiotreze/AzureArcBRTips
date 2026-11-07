# Azure Arc – Connected Machine Agent Version Compliance (Workbook)

[English](README.md) · [Português](README.pt-BR.md)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-agent-support-azuredeploy.json)

> ⚠️ **Personal, independent project – not an official Microsoft tool.** Provided *as is*, without warranty; see the repository [disclaimer](../../DISCLAIMER.md). Support status is an **estimate** (Azure APIs do not expose release dates) – validate against the [agent release notes](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes). You are responsible for how you use it.

Azure Monitor workbook for Azure Arc-enabled servers. **Current version: 4.7.0** (see the [CHANGELOG](CHANGELOG.md)). It answers three questions:

1. Are my **Connected Machine agents likely within the support window and above the configured minimum version**?
2. Is **automatic agent upgrade** enabled and working?
3. **What must be fixed**, and on which servers?

Support is estimated from sequential release numbers, not verified release dates; being above the configured minimum is not proof that all security fixes are installed. The reference is read live from Azure (auto-upgrade target and the Hybrid Compute exact `latest` endpoint), subject to the explicit manual override below. The unstable paged agent list is not used. Downloads are looked up by exact version; the optional Windows/Linux download override does not change compliance. No complete release catalog is claimed. Bilingual UI (English / Português). Read-only.

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
| 8 | Extensions | Extensions by publisher, type and region: auto-upgrade coverage, versions vs. the regional Azure catalog, issues grouped by cause |

Controls: *Show guide* adds the legend, methodology and official sources. *Show changelog* (Edit mode) shows the editorial history inside the workbook.

For publication, follow the [revision tracking workflow](CHANGELOG.md#azure-revision-tracking). Record the currently published Azure revision in the new editorial row **before** saving; Azure generates the next revision automatically. GitHub publication alone does not update a deployed workbook.

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

For an **update**, reuse the existing GUID with `--parameters workbookId=<existing-workbook-guid>` in the CLI command. Omitting it evaluates `newGuid()` again and creates another workbook. For reproducible deployments, replace `main` in the template URL with the reviewed commit SHA. Export the existing resource before updating; retain that backup for rollback. See [ARM newGuid behavior](https://learn.microsoft.com/azure/azure-resource-manager/templates/template-functions-string#newguid) (verified on 2026-11-06).

**Permissions:** Reader on the subscriptions / management group to query data. Deploying the ARM template or saving the workbook requires additional permissions to deploy/create or update the workbook resource. Queries are read-only; deployment creates a resource.

## Validation

[`scripts/Test-ArcWorkbookQueries.ps1`](../../scripts/Test-ArcWorkbookQueries.ps1) resolves the workbook's supported parameter types and runs visible queries across all tabs against your tenant (read-only). It evaluates inherited group visibility and reports status, rows, duration, HTTP 429 throttling and incomplete results. Requires PowerShell 7+, Az.Accounts and Reader on the subscriptions. It uses the ARG REST response to inspect pagination metadata. This is not a replacement for clicking through the portal. Run from the repository root:

```powershell
Connect-AzAccount -Tenant <tenant-id>
# offline lint (no Azure call)
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -DryRun
# every filter value one at a time + the first 3 extension drill-downs
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Language EN -FilterCombos OneFactor -ExtensionDrill 3
# open each tab like the portal (all its queries at once) with the optional charts on – reproduces HTTP 429
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Burst -SetParam @{ ShowCharts = 'Yes' }
# all non-empty filter subsets and explicit All selections; identical expanded queries run once per invocation
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Subscriptions <subscription-id> -Language EN -FilterCombos Subsets -CacheQueries -SetParam @{ ShowCharts = 'Yes' }
# every extension-region row and every published version offered by its comparison table
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Subscriptions <subscription-id> -Language PT -ExtensionDrill 10000 -AllExtensionTargets -CacheQueries
```

Results go to `./workbook-test-results` (excluded by `.gitignore`). With the charts on, the Overview tab runs 10 Resource Graph queries at once; the script retries an occasional HTTP 429 automatically.

Repeat the tests in **both EN and PT**. `Subsets` covers the enumerated filter options available in that run, not arbitrary future options or every text input. Test editable text parameters separately with documented boundary cases. `CacheHit=True` identifies reuse of the exact expanded query and subscription scope within one run; do not use caching to measure repeated-request latency or throttling. Burst never uses that cache.

`-SetParam` values take effect before dependent parameters are resolved. Query failures, unresolved tokens, parameter failures and **INCOMPLETE** results produce exit code **1**; success produces **0**. Missing continuation tokens do not prove completeness. Exactly 10,000 rows are complete only when response metadata confirms there are no more. Parameter failures appear in the CSV and the red final summary. Run the offline mock regression tests with `pwsh -NoProfile -File .\scripts\Test-ArcWorkbookQueries.Tests.ps1`.

During normal execution, parameters awaiting only values exported by query row selection are reported as **Skipped (aguarda seleção)** in the CSV and summary, without failing the run. Export names are discovered from query metadata. `-ExtensionDrill` supplies selection values and validates the parameter queries; a real failure or an unresolved non-selection token still produces exit code **1**.

Agent references use exact `latest` lookups, and agent downloads use an exact `major.minor` version. Leave the download-only override empty to use the current reference; an unavailable version produces an API error. Extension catalogs use ARM `GETARRAY` to follow continuation links, as [documented for workbook ARM sources](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-data-sources#azure-resource-manager). Extension comparisons retain the selected region, matching the [regional metadata API](https://learn.microsoft.com/rest/api/hybridcompute/extension-metadata-v-2/list). Verified on 2026-11-06. Grids remain limited to 1,000 rows where configured; they are not an unlimited fleet export.

> Test reports contain environment data – treat them as confidential and never attach them to issues or commits.

## Related

- [Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) – point-in-time security assessment; this workbook is the continuous view of the agent/extension part.
- [Manage Azure Connected Machine agent versions](https://learn.microsoft.com/azure/azure-arc/servers/manage-agent) · [Resolve Advisor recommendations for Arc-enabled servers](https://learn.microsoft.com/azure/azure-arc/servers/resolve-azure-advisor-recommendations)

See [CHANGELOG](CHANGELOG.md).
