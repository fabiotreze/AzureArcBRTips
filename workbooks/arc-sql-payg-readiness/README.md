# SQL Server enabled by Azure Arc – PAYG Readiness Workbook

Azure Workbook that shows, in one place, how ready your **SQL Server instances enabled by Azure Arc** are for **pay-as-you-go (PAYG)** licensing, and what to check before and after a transition.

> **Personal, unofficial project.** It is not a Microsoft product and not an official licensing tool. Core numbers are estimates, not meters. Confirm entitlement with your licensing process and charges in Cost Management. See [DISCLAIMER](../../DISCLAIMER.md).

**Version:** 2.2.2 · **Languages:** English / Português (switch with the *Language* parameter) · **Mode:** read-only (Azure Resource Graph; nothing is changed in your environment)

[Português](README.pt-BR.md) · [Changelog](CHANGELOG.md) · Workbook file: [`arc-sql-payg-readiness-workbook.json`](../arc-sql-payg-readiness-workbook.json)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-sql-payg-readiness-azuredeploy.json)

## What it answers
- Which Arc-enabled SQL Server instances are already PAYG, which are not, and which license types are in use (LicenseOnly, Paid, PAYG).
- What the official `manage-payg-transition.ps1` script **would** convert, and which hosts need attention first (🔴 🟠 🟢 priority).
- What is missing before a safe transition: SQL extension, ESU gap (SQL Server 2014/2016), **CSP consent for recurring PAYG billing**, connectivity (check-in older than 30 days), pCore versus billing plan alignment, auto-deploy tags.
- An estimate of cores per instance (per OSE: minimum 4, Standard maximum 24, free editions 0) and VM versus physical signals.

## Quick path
1. **Summary**: footprint, license mix, versions, support status.
2. **PAYG review**: start with 🔴 hosts; see what the script would convert.
3. **Validation**: ESU, CSP consent, connectivity, pCore.
4. Run the official script with `-ReportOnly` and reconcile.
5. Pilot a small approved set with `-WaitForCompletion`.
6. Confirm in Cost Management and set the auto-deploy tag.

The *How to use* tab has buttons that jump to each tab and links to the script, README and Microsoft Learn pages.

## Tabs
| Tab | Use it for |
|---|---|
| How to use | Purpose, quick path with direct links, limits |
| Summary | Tiles, license mix, versions, support status |
| PAYG review / exports | Per-host priority, what the script would convert, next action, reconciliation backlog |
| Complete inventory / export | Full evidence, exportable (grids up to 10,000 rows, with search) |
| Architecture / sizing | VM versus physical signal, core estimate, pCore and unlimited virtualization options |
| Validation | ESU, CSP consent, connectivity, pCore, auto-deploy tags, missing extension |
| References | Official documentation used |

## Requirements
- Azure Reader (or higher) on the subscriptions you select.
- Azure Resource Graph access. No extra resource provider or agent is needed in the workbook itself.
- Servers and SQL instances already onboarded to Azure Arc with the SQL Server extension.

## Import
1. Azure portal → **Monitor** (or **Azure Arc**) → **Workbooks** → **New**.
2. Open the **Advanced Editor** (`</>`), choose **Gallery Template**, paste the content of [`arc-sql-payg-readiness-workbook.json`](../arc-sql-payg-readiness-workbook.json) and select **Apply**.
3. Select **Save**, choose the subscription, resource group and region.

## Validation performed
- 18 Azure Resource Graph queries run against a test tenant in Portuguese and English: **18/18 OK, 0 failures**.
- Throttling: each tab runs at most 8 queries (Azure Resource Graph allows about 15 per 5 seconds per user). A stress test that switched tabs back to back produced a few HTTP 429 responses that recovered on retry.
- Test scripts: [`scripts/Test-ArcWorkbookQueries.ps1`](../../scripts/Test-ArcWorkbookQueries.ps1).
- A small lab does not prove behavior at scale. Validate in your own environment before using the results for decisions.

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
