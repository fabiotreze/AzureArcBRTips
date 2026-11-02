# Changelog – SQL Server enabled by Azure Arc – PAYG Readiness Workbook

## 2.2.2 – 2026-11-02
- **Quick path with direct links** (*How to use* tab, EN/PT): buttons jump to Summary, PAYG review and Validation; steps 4–6 link to the script, README, Microsoft Learn (PAYG transition, auto-deploy) and Cost Management.
- No query changed. Tested: 18/18 queries OK (PT and EN), no failures.

## 2.2.1 – 2026-10-31
- Single, shorter base query; no regex; one bilingual tab bar (EN / PT).
- Core estimate per machine (minimum 4, Standard maximum 24, free editions 0, Linux HADR billed as active).
- Backlog without healthy PAYG hosts; "Would the script convert?" column and conversion risk (LicenseOnly, Server+CAL, pCore).
- New checks: ESU for SQL 2014/2016, connectivity older than 30 days, CSP consent, pCore versus billing plan alignment.
- Priority 🔴🟠🟢, tiles, charts, grids up to 10,000 rows with search.
- References corrected. Read-only: no resource is changed.
