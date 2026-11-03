# Changelog – SQL Server enabled by Azure Arc – PAYG Readiness Workbook

## 2.2.3 – 2026-11-03
- **Revision tracking:** new editorial row references the currently published Azure revision `ead30319b3554eca9eed11985b6bcd31`; missing historical IDs are explicitly marked *Not recovered / Não recuperada*, preserving the recorded IDs through 2.1.
- Corrected the before-save workflow (EN/PT), synchronized the deployment template and updated the guides.
- No query changed. GitHub publication does not update the deployed workbook.

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

## Azure revision tracking

The embedded editorial history uses **Previous published revision**: the Azure revision published immediately before a new editorial update. Azure assigns revision IDs automatically on save; they are not editorial version numbers, resource IDs or Git commits.

1. Before publishing, read the current revision from the target workbook's Azure revision history.
2. Add the new editorial row with UTC date/time, version, description and that current revision ID.
3. Keep workbook JSON, deployment template, guides and this changelog synchronized.
4. Save/publish to Azure and verify the new content and revision. Use that new ID for the next update.
5. Publish the matching files to GitHub. A GitHub push alone does not update Azure.

**Not recovered / Não recuperada** identifies older IDs that were not recorded and could not be recovered from the available Azure history. Existing recorded IDs are preserved. The recorded IDs refer to the reference deployment; other deployments have their own resource and revision IDs.

**Português:** antes de publicar, consulte a revisão atual no histórico do workbook no Azure e registre esse ID na nova linha editorial, com data/hora UTC, versão e descrição. Sincronize JSON, template, guias e changelog. Após salvar/publicar no Azure, confira o conteúdo e o novo ID, que será usado na próxima atualização. Publique os arquivos correspondentes no GitHub; o push não atualiza o Azure. IDs históricos não recuperados são identificados explicitamente, sem inventar valores. Os IDs registrados pertencem à implantação de referência.
