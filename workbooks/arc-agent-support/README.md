# Azure Arc – Connected Machine Agent Version Compliance (Workbook)

> ⚠️ **Personal, independent project – not an official Microsoft tool.** Provided *as is*, without warranty; see the repository [disclaimer](../../DISCLAIMER.md). Support status is an **estimate** (Azure APIs do not expose release dates) – validate against the [agent release notes](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes). You are responsible for how you use it.

**Current version: 4.9.0** · **Languages:** English / Português · **Mode:** read-only queries; deploying or saving creates or updates a workbook resource, without upgrading agents or changing the inventoried servers.

[English](README.md) · [Português](README.pt-BR.md) · [Changelog](CHANGELOG.md) · Workbook file: [`arc-agent-support-workbook.json`](../arc-agent-support-workbook.json)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-agent-support-azuredeploy.json)

## What it answers

Azure Monitor workbook for Azure Arc-enabled servers. It answers three questions:

1. Are my **Connected Machine agents likely within the support window and above the configured minimum version**?
2. Is **automatic agent upgrade** enabled and working?
3. **What must be fixed**, and on which servers?

Support is estimated from sequential release numbers, not verified release dates; being above the configured minimum is not proof that all security fixes are installed. The reference is read live from Azure (auto-upgrade target and the Hybrid Compute exact `latest` endpoint), subject to the explicit manual override below. The unstable paged agent list is not used. Downloads are looked up by exact version; the optional Windows/Linux download override does not change compliance. No complete release catalog is claimed.

## Quick path

1. Select subscriptions, language and filters.
2. Open **Overview** and review the servers that need action.
3. Use **Server inventory** and **Automatic agent upgrade** to inspect the evidence.
4. Review **Latest reference & manual upgrade paths**, **Advisor**, **Policy** or **Extensions** as needed.
5. Validate recommendations against official sources before making changes outside the workbook.

## Tabs

| # | Section | What it shows |
|---|---|---|
| 1 | Overview | Banner when servers are disconnected / expired; *Fleet status* and *Version & upgrade* tiles (Latest / Supported / Out of support / **Below security floor** / auto-upgrade); **Servers that need action** with the reason (disconnected/expired, below security floor, out of support, failing/lagging upgrade, manual upgrade needed). Servers that only have automatic upgrade disabled while eligible are a separate *Eligible, not enabled* recommendation tile, not counted as *Needs action* |
| 2 | Distribution | Versions, connection status, auto-upgrade health (charts are optional: *Show distribution charts*, off by default) |
| 3 | Azure Advisor | Blockers (expired / disconnected) and agent recommendations, with a link to the impacted resources in Advisor and a freshness check |
| 4 | Server inventory | One row per server (up to 1000), below-floor and out-of-support first |
| 5 | Automatic agent upgrade | Eligibility (agent 1.67+), health (On track / Lagging / Failing / Blocked), last attempt |
| 6 | Latest reference & manual upgrade paths | Latest per OS and its source; next step per installed version; agent download by exact version (latest pre-selected) |
| 7 | Azure Policy | Only agent / automatic-upgrade policies, with an explicit message when none is assigned |
| 8 | Extensions | Extensions by publisher, type and region: auto-upgrade coverage, versions vs. the regional Azure catalog, issues grouped by cause |

Controls: *Show guide* adds the legend, methodology and official sources. *Show changelog* (Edit mode) shows the editorial history inside the workbook.

Extension catalogs use the merged root array returned by [ARM GETARRAY](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-data-sources#azure-resource-manager) (verified on 2026-11-06). If no versions are returned, comparison and upgrade outlook remain unknown; installed-only does not prove a version was withdrawn. Enabled automatic upgrade is not a guarantee of rollout.

## Requirements

Reader on the selected subscriptions / management group is required to query data. Deploying the ARM template or saving the workbook requires additional permissions to deploy/create or update the workbook resource. For query validation, use PowerShell 7+ and Az.Accounts.

### Filters and controls (visible parameters)

| Parameter | Default | Meaning |
|---|---|---|
| Subscriptions | All | Subscriptions queried (Azure Resource Graph) |
| Language | EN | Single EN / PT switch for every text in the workbook |
| OsFilter (OS) | All | Operating systems found in the selected subscriptions |
| StatusFilter (Connection Status) | All | Connection statuses found in the selected subscriptions |
| SupportFilter (Estimated support status) | All | Latest / Supported / Out of support / Unknown (heuristic, see Rules) |
| AutoUpgradeFilter (Auto Upgrade) | All | Enabled / Disabled / N/A |
| ShowInfo (Show guide) | No | Legend, methodology and official sources |
| ShowCharts (Show distribution charts) | No | Optional charts on Distribution; opening the tab runs 6 extra queries |
| ShowChangelog | No | Editorial history (Edit mode only) |

The remaining parameters are hidden: the *Rules* below, the Azure API versions (`ApiVersion`, `ExtApiVersion`) and values resolved from Azure (`ReleasedWindows`, `ReleasedLinux`, `LatestSummary`, `AnyOsTarget`, `SelectedTab`). On the Extensions tab, selecting a row of the first grid exports `ExtPublisher`, `ExtType` and `ExtLocation` to the comparison grids.

The extension catalog request uses the tenant-level path without `/subscriptions/{id}`. On 2026-11-10 it returned HTTP 200 with the same version list as the documented subscription path for one publisher/type/region ([API reference](https://learn.microsoft.com/rest/api/hybridcompute/extension-metadata-v-2/list)); other regions and publishers were not tested.

### Rules (editable in Edit mode)

| Parameter | Default | Meaning |
|---|---|---|
| SupportWindow | 12 releases | Heuristic only: approximates the official last-12-months policy using sequential release numbers; verify release dates in the agent release notes (the [release notes](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes) say only versions released within the last year are supported; checked 2026-11-10) |
| AutoUpgradeTolerance | 1 | Heuristic, not a documented guarantee (Microsoft rolls automatic upgrades out in batches and retries failures); *On track* also requires connectivity and no failed last attempt |
| MinAutoUpgradeVersion | 1.67 | Automatic agent upgrade requires agent 1.67 or later (Windows: PowerShell execution policy RemoteSigned; Linux: cron service); [Learn](https://learn.microsoft.com/azure/azure-arc/servers/automatic-agent-upgrade), verified 2026-11-10 |
| **SecurityFloorVersion** | **1.61** | Configurable minimum based on public CVE records (CVE-2026-26117 affects agents < 1.61, CVE-2025-49692 < 1.49; CVE-2025-26627 and CVE-2025-55316 as in Arc Posture Review); applied to every OS; being at/above it does **not** certify security. Review new security fixes and this threshold regularly. CVE-2026-26117 record (affected < 1.61) checked 2026-11-10; the 1.70 release notes list security fixes without affected-version ranges, so the floor was not raised |
| LatestOverride | empty | Optional manual reference taken from the agent release notes. When filled it takes priority over every other source (it is not a maximum), even if Azure reports a higher version: update or clear it after each release |

Without an override, *Latest* is the highest of the version Azure reports (`osType/agentVersions/latest`) and the auto-upgrade target seen in the fleet, and it can lag the newest release. Verified on 2026-11-10: the release notes and the download host already listed 1.70 (host `Last-Modified` 2026-11-09) while the API still returned 1.69. No Azure Resource Graph or ARM source tells the newest release immediately, so a fixed version cannot be removed without accepting that lag; set *LatestOverride* temporarily if you need the newest release counted. The download selector pre-selects the version confirmed by the API, so a newer override does not produce a 404.

## Import

- **Deploy to Azure** button above → pick subscription / resource group → open in *Azure Monitor → Workbooks*.
- **Azure CLI**: `az deployment group create -g <resource-group> --template-uri https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/main/templates/arc-agent-support-azuredeploy.json`
- **Manual**: Workbooks → New → *Advanced Editor* (`</>`) → paste [`arc-agent-support-workbook.json`](../arc-agent-support-workbook.json) → Apply → Save.

For an **update**, reuse the existing GUID with `--parameters workbookId=<existing-workbook-guid>` in the CLI command. Omitting it evaluates `newGuid()` again and creates another workbook. For reproducible deployments, replace `main` in the template URL with the reviewed commit SHA. Export the existing resource before updating; retain that backup for rollback. See [ARM newGuid behavior](https://learn.microsoft.com/azure/azure-resource-manager/templates/template-functions-string#newguid) (verified on 2026-11-06).

For publication, follow the [revision tracking workflow](CHANGELOG.md#azure-revision-tracking). Record the currently published Azure revision in the new editorial row **before** saving; Azure generates the next revision automatically. GitHub publication alone does not update a deployed workbook.

## Validation

[`scripts/Test-ArcWorkbookQueries.ps1`](../../scripts/Test-ArcWorkbookQueries.ps1) resolves the workbook's supported parameter types and runs visible queries across all tabs against your tenant (read-only). It evaluates inherited group visibility and reports status, rows, duration, HTTP 429 throttling and incomplete results. It uses the ARG REST response to inspect pagination metadata. This is not a replacement for clicking through the portal. Run from the repository root:

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

**Metadata contract check (not a result test).** `pwsh -NoProfile -File .\scripts\Test-ArcWorkbookContract.ps1` compares every `properties.*` path, resource type, Resource Graph table and ARM path used by the workbooks with the public sources: the Azure REST API specs (`Azure/azure-rest-api-specs`) and the Learn list of Resource Graph supported tables. `-Live` (read-only) also counts how many resources in your tenant populate each property. It proves the workbook reads documented fields; it does not prove that the heuristics (supported, on track, needs action) match Microsoft policy. Advisor, policy and subscription properties are reported as UNVERIFIED because no spec is compared for them. Offline tests: `Test-ArcWorkbookContract.Tests.ps1`.

During normal execution, parameters awaiting only values exported by query row selection are reported as **Skipped (aguarda seleção)** in the CSV and summary, without failing the run. Export names are discovered from query metadata. `-ExtensionDrill` supplies selection values and validates the parameter queries; a real failure or an unresolved non-selection token still produces exit code **1**.

> Test reports contain environment data – treat them as confidential and never attach them to issues or commits.

## Official documentation

- [Manage Azure Connected Machine agent versions](https://learn.microsoft.com/azure/azure-arc/servers/manage-agent) · [Resolve Advisor recommendations for Arc-enabled servers](https://learn.microsoft.com/azure/azure-arc/servers/resolve-azure-advisor-recommendations)
- [Agent release notes](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes)

## Known limits

Agent references use exact `latest` lookups, and agent downloads use an exact `major.minor` version. Leave the download-only override empty to use the current reference; an unavailable version produces an API error. Extension catalogs use ARM `GETARRAY` to follow continuation links, as [documented for workbook ARM sources](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-data-sources#azure-resource-manager). Extension comparisons retain the selected region, matching the [regional metadata API](https://learn.microsoft.com/rest/api/hybridcompute/extension-metadata-v-2/list). Verified on 2026-11-06. Grids remain limited to 1,000 rows where configured; they are not an unlimited fleet export.

## Maintenance

After each Connected Machine agent release, check the [agent release notes](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes) and update or clear `LatestOverride` (see Rules). No file in this repository tracks release dates.

## Related projects

- [Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) – point-in-time security assessment; this workbook is the continuous view of the agent/extension part.

See [CHANGELOG](CHANGELOG.md).
