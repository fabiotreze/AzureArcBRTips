# SQL Server enabled by Azure Arc – PAYG Readiness Workbook

Azure Workbook that shows, in one place, how ready your **SQL Server instances enabled by Azure Arc** are for **pay-as-you-go (PAYG)** licensing, and what to check before and after a transition.

> **Personal, unofficial project.** It is not a Microsoft product and not an official licensing tool. Core numbers are estimates, not meters. Confirm entitlement with your licensing process and charges in Cost Management. See [DISCLAIMER](../../DISCLAIMER.md).

**Version:** 2.4.7 · **Languages:** English / Português (switch with the *Language* parameter) · **Mode:** read-only queries (Azure Resource Graph); deploying or saving creates or updates a workbook resource, without changing the inventoried servers or their licensing.

[Português](README.pt-BR.md) · [Changelog](CHANGELOG.md) · Workbook file: [`arc-sql-payg-readiness-workbook.json`](../arc-sql-payg-readiness-workbook.json)

For publication, follow the [revision tracking workflow](CHANGELOG.md#azure-revision-tracking). Record the currently published Azure revision in the new editorial row **before** saving; Azure generates the next revision automatically. GitHub publication alone does not update a deployed workbook.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-sql-payg-readiness-azuredeploy.json)

## What it answers
- Which Arc-enabled SQL Server instances are already PAYG, which are not, and which license types are in use (LicenseOnly, Paid, PAYG).
- What the official `manage-payg-transition.ps1` script **would** convert, and which hosts need attention first (🔴 🟠 🟢 priority).
- What is missing before a safe transition: SQL extension, ESU gap (SQL Server 2014/2016), **CSP consent for recurring PAYG billing**, connectivity (check-in older than 30 days), pCore versus billing plan alignment, auto-deploy tags.
- A per-host core-capacity approximation (minimum 4; Standard 24 through SQL Server 2022 and 32 for 2025; free editions 0), with unknown values preserved, and VM versus physical signals. This is not a licensing requirement or billing meter.

The Standard limits describe [engine compute capacity](https://learn.microsoft.com/sql/sql-server/compute-capacity-limits-by-edition-of-sql-server), not a universal billing cap. Mixed hosts use the limit of their Standard instances, not a Developer instance's version. Reconcile physical-host and VM licensing separately using [Microsoft Learn](https://learn.microsoft.com/sql/sql-server/azure-arc/manage-license-billing) and Cost Management. Verified on 2026-11-06.

## Guided path (8 steps)
1. **Scope**: select the subscriptions.
2. **Baseline** (Summary): hosts with SQL instances versus hosts with an Arc machine in ARG, Arc not connected, license mix, 🔴 hosts.
3. **Fix the base** (Inventory, Validation): hosts without an Arc machine, disconnected agents, missing extension.
4. **Triage** (PAYG review): 🔴 then 🟠; decide which hosts to exclude.
5. **Cores** (Architecture): VM versus physical, core estimate, pCore.
6. **Prerequisites** (Validation): ESU, CSP consent, tags, SQLServerLicense, pCore.
7. **Dry run**: official script with `-ReportOnly`, compared with *Script would select (ARG)*.
8. **Pilot and confirm**: `-WaitForCompletion` on a small set, Cost Management, auto-deploy tag.

The *How to use* tab explains each step (where to look, what to do, when it is done) and has buttons that jump to each tab and links to the script and Microsoft Learn pages.

## Before/after snapshot scripts (optional, outside the workbook)

The workbook shows only the current state and keeps no history. Two read-only PowerShell 7 scripts (module `Az.Accounts`, ARG reads only) let you record the state before and after a PAYG change and compare them. They work for any path: direct PAYG or PAYG with physical core license (unlimited virtualization).

```powershell
Connect-AzAccount
.\scripts\Export-ArcSqlPaygSnapshot.ps1 -Label Before      # CSV in .\arc-payg-snapshots
# ... apply the change (for example the official script, with -WaitForCompletion) ...
.\scripts\Export-ArcSqlPaygSnapshot.ps1 -Label After
.\scripts\Compare-ArcSqlPaygSnapshot.ps1 -Before <before.csv> -After <after.csv> [-PlannedHostsCsv planned.csv]
```

- One row per host. `Scenario`: `DirectPAYG` (LicenseType PAYG), `PhysicalCoreLicense` (UsePhysicalCoreLicense applied), `NotPAYG`, `Unknown` (no Arc machine or no extension).
- `Check` is `OK`, `INFO` or `ATTENTION`. Findings include NO_MACHINE, ARC_NOT_CONNECTED, EXT_MISSING, EXT_NOT_SUCCEEDED, ESU_MISSING, PCORE_NO_LICENSE_VISIBLE and PCORE_PLAN_MISMATCH.
- Compare lists scenario transitions, changed fields per host, and, with `-PlannedHostsCsv` (column `MachineName` or `HostId`), whether each planned host is `CONVERTED`, `CONVERTED_WITH_ATTENTION`, `NOT_CONVERTED` or `NOT_FOUND_AFTER`.
- Cores are estimates, not billing. How long ARG takes to reflect a change is not verified; take the After snapshot once the change has propagated. The CSVs contain subscription IDs and host names: they are git-ignored, keep them private.
- Offline tests: `scripts\Test-ArcSqlPaygSnapshot.Tests.ps1`.

## Tabs
| Tab | Use it for |
|---|---|
| How to use | Purpose, 8-step guided path with direct links, limits |
| Summary | Tiles (hosts with SQL instances, hosts with an Arc machine in ARG, instances without an Arc machine (possibly stale), Arc not connected, license mix), versions, support status |
| PAYG review / exports | Per-host priority, what the script would convert, next action, reconciliation backlog |
| Complete inventory / export | Full evidence, exportable (grids up to 10,000 rows, with search) |
| Architecture / sizing | VM versus physical signal, core estimate, pCore and unlimited virtualization options |
| SQL on Azure VMs | `Microsoft.SqlVirtualMachine` (Azure VMs, not Arc): license type PAYG / AHUB / DR by edition, paid-edition review list. Software Assurance and vCores are not visible; DR is the free HA/DR replica; `NotSet` and `Unknown` returned by the API are shown as Not reported. Sources: [license model](https://learn.microsoft.com/azure/azure-sql/virtual-machines/windows/licensing-model-azure-hybrid-benefit-ahb-change) and the 2023-10-01 API spec (verified on 2026-11-10); portal rendering not verified |
| Validation | ESU, CSP consent, connectivity, pCore, auto-deploy tags, missing extension, PAYG change history (ARG `resourcechanges`) |
| References | Official documentation used |

## Requirements
- Azure Reader (or higher) on the subscriptions you select.
- Azure Resource Graph access. No extra resource provider or agent is needed in the workbook itself.
- Servers and SQL instances already onboarded to Azure Arc with the SQL Server extension.

## Import
1. Azure portal → **Monitor** (or **Azure Arc**) → **Workbooks** → **New**.
2. Open the **Advanced Editor** (`</>`), choose **Gallery Template**, paste the content of [`arc-sql-payg-readiness-workbook.json`](../arc-sql-payg-readiness-workbook.json) and select **Apply**.
3. Select **Save**, choose the subscription, resource group and region.

For an **ARM update**, reuse the existing resource GUID:

```azurecli
az deployment group create --resource-group <resource-group> --template-file templates/arc-sql-payg-readiness-azuredeploy.json --parameters workbookId=<existing-workbook-guid>
```

The default `newGuid()` creates a new workbook when omitted; see [ARM behavior](https://learn.microsoft.com/azure/azure-resource-manager/templates/template-functions-string#newguid) (verified on 2026-11-06). Back up the current resource before updating. For reproducibility with remote templates, replace `main` with the reviewed commit SHA. Retain the previous template and the same GUID for rollback.

## Validation performed
- 18 Azure Resource Graph queries run against a test tenant in Portuguese and English: **18/18 OK, 0 failures**.
- Throttling: each tab runs at most 8 queries (Azure Resource Graph allows about 15 per 5 seconds per user). A stress test that switched tabs back to back produced a few HTTP 429 responses that recovered on retry.
- Test scripts: [`scripts/Test-ArcWorkbookQueries.ps1`](../../scripts/Test-ArcWorkbookQueries.ps1).
- The validator applies `-SetParam` before resolving dependent parameters and exits **1** for query failures, unresolved tokens or parameter failures; otherwise **0**. Parameter failures appear in the CSV and the red final summary. Offline mock regression tests: `pwsh -NoProfile -File .\scripts\Test-ArcWorkbookQueries.Tests.ps1` (from the repository root).
- Parameters awaiting only query row-selection exports are reported as **Skipped (aguarda seleção)** without failing normal execution; export names are discovered from query metadata. Drill-down validation remains strict, and unresolved non-selection tokens still fail.
- A small lab does not prove behavior at scale. Validate in your own environment before using the results for decisions.

The harness uses ARG REST pagination metadata; **INCOMPLETE** results fail validation, including in Burst mode. Host-level inventory/review queries retain `id` for continuation tokens. A 10,000-row grid setting does not guarantee that the data source returned every record. See [ARG pagination](https://learn.microsoft.com/azure/governance/resource-graph/concepts/work-with-data) and [workbook limits](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-limits) (verified on 2026-11-06).

Run `-DryRun`, normal mode and `-Burst` in both languages with an explicit `-Subscriptions <subscription-id>` scope. Test every tab and guided-path button in the portal too; API tests do not verify rendering or navigation.

## Official documentation
- [Manage SQL Server license and billing](https://learn.microsoft.com/sql/sql-server/azure-arc/manage-license-billing)
- [Transition to pay-as-you-go](https://learn.microsoft.com/sql/sql-server/azure-arc/manage-pay-as-you-go-transition)
- [Auto-deploy the SQL Server extension](https://learn.microsoft.com/sql/sql-server/azure-arc/manage-autodeploy)
- [Manage license type at scale](https://learn.microsoft.com/sql/sql-server/manage-license-type-at-scale)
- [Extended Security Updates](https://learn.microsoft.com/sql/sql-server/azure-arc/extended-security-updates)
- [`manage-payg-transition.ps1` (sql-server-samples)](https://github.com/microsoft/sql-server-samples/blob/e1163bff690ef8b3109d83dd139ffdf1a40219da/samples/manage/manage-payg-transition/manage-payg-transition.ps1)

## Known limits
- The "would the script convert?" column is an approximation of a pinned version of the script (commit `e1163bf`). Re-read the script before running it.
- The workbook cannot see entitlement (Software Assurance), billing or CSP agreements.
- ESU hints in the grid carry no dates. Per the Microsoft Learn lifecycle pages (verified on 2026-11-10), extended support ended for [SQL Server 2014](https://learn.microsoft.com/lifecycle/products/sql-server-2014) on 2024-07-09 and for [SQL Server 2016](https://learn.microsoft.com/lifecycle/products/sql-server-2016) on 2026-07-14; ESU year boundaries were not verified here.
- The extension `settings` keys `enableExtendedSecurityUpdates`, `UsePhysicalCoreLicense.IsApplied` and `ConsentToRecurringPAYG.Consented`/`ConsentTimestamp` are free-form in the ARM spec, so the contract check cannot validate them. Their names and casing match the [official `modify-arc-sql-license-type.ps1`](https://github.com/microsoft/sql-server-samples/blob/master/samples/manage/azure-arc-enabled-sql-server/modify-license-type/modify-arc-sql-license-type.ps1) (verified on 2026-11-10). In the author's lab none of the three was populated, so the columns show "not reported" there and were not observed with real values.- Azure Resource Graph returns at most 1,000 records per call by default ([Learn](https://learn.microsoft.com/azure/governance/resource-graph/concepts/work-with-data)); whether the Workbooks grid pages beyond that with the 10,000-row limit is not verified. Confirm in large estates.
