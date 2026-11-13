# Copilot instructions – AzureArcBRTips

Personal, independent repository (owner: Fabio Rodrigues Vieira Costa). It is **not** an official Microsoft product or documentation. Every user-facing document keeps that statement and links to `DISCLAIMER.md`.

## Repository model (follow it for every project)
Each project is a self-contained unit with the same layout:

```
workbooks/<project>-workbook.json            # the Azure Workbook (Gallery Template JSON)
workbooks/<project>/README.md                # English guide
workbooks/<project>/README.pt-BR.md          # Portuguese (Brazil) guide
workbooks/<project>/CHANGELOG.md             # per-project versions (independent of the repo)
templates/<project>-azuredeploy.json         # ARM template embedding the workbook ("Deploy to Azure" button)
scripts/                                      # shared tooling (Test-ArcWorkbookQueries.ps1 and its offline mock tests Test-ArcWorkbookQueries.Tests.ps1, which must pass after any change to the harness; Test-ArcWorkbookContract.ps1 checks queries against public Microsoft metadata, with offline tests Test-ArcWorkbookContract.Tests.ps1)
README.md / README.pt-BR.md                  # root: "Project catalog" table, one row per project
```
Current projects: `arc-agent-support` (Connected Machine agent compliance), `arc-sql-payg-readiness` (SQL Server enabled by Azure Arc – PAYG readiness) and `arc-sql-resource-reconciliation` (SQL resource relationship and metadata exceptions).

## Rules that always apply
1. **Bilingual.** Every user-facing doc exists in English and Portuguese (pt-BR). Change one, change the other in the same commit.
2. **Independent versions.** A project version is not a repo version. Update, together: the workbook's editorial changelog (inside the JSON), `workbooks/<project>/CHANGELOG.md`, the "Current version" line in both project READMEs, and the ARM template.
3. **Do not hand-edit workbook JSON** (150–370 KB). Change it with a script or ask for the change to be generated; never let a tool reformat or truncate it. Always validate it parses as JSON afterwards.
4. **The ARM template is generated from the workbook.** After any workbook change, regenerate `templates/<project>-azuredeploy.json` (clone the existing template, replace `serializedData`; set contentVersion to the project version; workbookId stays [newGuid()]) and commit both together.
5. **Catalog.** A new or renamed project needs one row in the root `README.md` ("Project catalog" table, not a loose section) and one in `README.pt-BR.md`, with English · Português · Changelog links.
6. **Files:** UTF-8 without BOM; Markdown tables start after a blank line; relative links only; no secrets, subscription IDs, tenant IDs or tokens anywhere (examples use placeholders).
7. **Facts need a source.** Licensing, support and API statements must be checked against Microsoft Learn (or the cited script/CVE record) and linked. If something could not be verified, write "not verified" instead of asserting it. Do not copy Microsoft documentation text; summarize and link.
8. **Read-only by design.** Workbooks only read (Azure Resource Graph / ARM GET). Never add actions that change customer resources.
9. **Never push.** Prepare commits locally; the owner pushes (account differences exist). Never change history that was already pushed.
10. **Dated facts.** Anything that can change (an API returning a version, support dates, prices) is written with "verified on <date>" and a source, never as a timeless statement.
11. **Describe overrides exactly as implemented.** `LatestOverride`, when filled, takes priority over every other source (it is not a maximum); banners, parameter descriptions, methodology text and READMEs must say so and tell the reader to update or clear it on each release.
12. **PowerShell safety.** `[regex]::Replace(input, pattern, replacement, 1)` treats `1` as RegexOptions.IgnoreCase, not a count; use `[regex]::new(pattern).Replace(input, replacement, 1)`. Scripts that rewrite files must back up first and say what they changed. Scripts and tests must not depend on the console encoding: compare accented text through the UTF-8 CSV or use ASCII tokens.

## Workbook design limits (learned in testing)
- Azure Resource Graph throttles at about **15 queries per 5 seconds per user**. Keep **≤ 8–10 ARG queries visible per tab**; hide inactive tabs with conditional visibility (hidden items do not run).
- Keep each query **≤ ~12,000 characters**; 15–17k character queries failed in the portal.
- One bilingual tab bar ("EN / PT" labels) driven by a single parameter. Two tab bars break navigation.
- Grids: set `rowLimit` explicitly (default 250); `tiles` stack vertically, so prefer compact tables for KPIs.
- Use ARG-supported KQL only (no `let`, limited `join`/`union`); every query must run in both languages.
- ARG limits (Microsoft Learn, "Understand the query language", checked 2026-11-12): at most 3 `join`/`union` in total (only one may be a cross-table join, unless all cross-table joins are Resources↔ResourceContainers); at most 3 `mv-expand`; `union` only inside one table or between Resources and ResourceContainers; a table cannot be the right side more than once (`DisallowedMaxNumberOfRemoteTables`). `policyresources` and `resourcechanges` cannot be combined with each other in a `union` (portal error `UnsupportedRemoteTableScenario`): use one query each.

## Lessons learned (evidence discipline)
- Never assume a table, property or value. Confirm it on Microsoft Learn, the REST spec, the SDK reference or Azure Policy aliases (`Get-AzPolicyAlias`) and record the source and date. If it cannot be confirmed, keep it UNVERIFIED and defer to Microsoft support; do not state it as fact.
- Third-party scripts and community sites (for example AzAdvertizer) are leads, not sources; label them as such.
- Inspect workbook queries by parsing the JSON per query name, not with raw-text regex: `resources | where` also matches inside `advisorresources | where`.
- Mock tests do not prove KQL semantics or ARG limits; real tenant runs and portal clicks do. Say what remains unverified.
- Do not retract or assert a claim based on one tenant: say how many scopes and records were observed.
- Classification rules come from the Microsoft catalog (Learn, REST specs, official queries). The test tenant only validates query structure, field types and execution failures; never present its sample size as a limit or as the basis of a rule. If a branch has no data in the tenant, force the condition in a test copy of the query to check the output. Example: the SQL extension health definition is in Learn "Troubleshoot Azure extension for SQL Server".
- Extension health: never trust the first token of a status message (a SQL agent `Healthy` can carry a failed plugin). Classify from the whole message, test the rules on real captured text, and state that the rules come from observed messages, not a Microsoft catalog.
- `instanceView.status` of Arc extensions has only `level`, `code` and `message`: there is no date in Azure Resource Graph. Show a date only when the extension writes it in its message, and say it is the last report, not the start of the problem.
- Harness: `-FilterCombos` takes `None|OneFactor|Full|Subsets` (`Full` ran for over 25 minutes without finishing; use `OneFactor`), and `-Subscriptions` is required or global parameters stay unresolved.

## Definition of done for any workbook change
1. JSON parses; no undefined `{Parameter}` references.
2. `scripts/Test-ArcWorkbookQueries.ps1` passes: `-DryRun`, `-Language PT`, `-Language EN`, `-Burst` (an occasional `OK_AFTER_429` is acceptable; failures are not).
3. Imported in the portal (Advanced Editor), tabs and buttons clicked in PT and EN.
4. Version, changelogs, READMEs (EN/PT), template and catalog updated (rules 2, 4, 5).
5. Commit message: imperative, English, mentions project and version, e.g. `Update SQL PAYG readiness workbook to v2.3.0 (...)`.

## How to answer in this repo
- Reply in the language of the file or of the user's message (Portuguese for pt-BR files).
- Be concise and structured: what changed, why, how it was validated, what remains unverified.
- Before editing, list the files you will touch. After editing, list what to run to validate.
- Ask before: deleting files, renaming projects, changing the layout above, or touching `LICENSE`, `LICENSE-DOCS`, `DISCLAIMER.md`, `CITATION.cff`, `SECURITY.md`.

See also: `.github/instructions/*.instructions.md` (path-specific rules) and `.github/prompts/new-workbook-project.prompt.md` (step by step for a new project).
