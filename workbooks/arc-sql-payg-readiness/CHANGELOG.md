# Changelog – SQL Server enabled by Azure Arc – PAYG Readiness Workbook

## 2.4.1 – 2026-11-10
- **Text only (PAYG review tab):** the note now gives a reading order for the three tables, the priority rule applied by the query (High, Medium, OK), a column legend, and notes on hosts without an Arc machine and on free/test editions (the script does not filter by edition). No query changed. Portal rendering not verified.
- **Português:** somente texto (aba Revisão PAYG): ordem de leitura das três tabelas, regra de prioridade da consulta (Alta, Média, OK), legenda das colunas e notas sobre hosts sem máquina Arc e edições gratuitas/teste (o script não filtra por edição). Nenhuma consulta alterada. Renderização no portal não verificada.

## 2.4.0 – 2026-11-10
- **New tab "SQL on Azure VMs":** license type summary (PAYG, AHUB, DR) by edition and a review list for paid editions of `Microsoft.SqlVirtualMachine`, joined to the compute VM by `virtualMachineResourceId`. Free editions (Developer, Express) are listed separately; DR is treated as the free HA/DR replica, not as "AHB off". Property names and enum values checked with `scripts/Test-ArcWorkbookContract.ps1` against the 2023-10-01 spec. Software Assurance and vCores are not visible. Not run against live SQL VMs; portal rendering not verified.
- **Português:** nova aba "SQL em VMs Azure": resumo por tipo de licença (PAYG, AHUB, DR) e edição, e lista de revisão das edições pagas de `Microsoft.SqlVirtualMachine`. Developer e Express separadas; DR é a réplica HA/DR gratuita. Propriedades conferidas com o script de contrato (spec 2023-10-01). Software Assurance e vCores não visíveis. Não executado em SQL VMs reais; renderização no portal não verificada.

## 2.3.3 – 2026-11-10
- **SQLServerLicense validation:** removed the `Scope` column (`properties.scope`), which is not in the `SqlServerLicense` API spec; the documented fields are `scopeType` and `tenantId` (checked with `scripts/Test-ArcWorkbookContract.ps1`). Portal rendering not verified.
- **Português:** validação de SQLServerLicense: coluna `Scope` removida (`properties.scope` não consta no spec; os campos documentados são `scopeType` e `tenantId`). Renderização no portal não verificada.

## 2.3.2 – 2026-11-10
- **Language parameter:** removed the non-standard `defaultValue` and the per-item `selected` flags; they appear to make the portal offer a *Default items* choice that sets a value outside EN/PT (red parameter). The initial value is now English, same as the agent-support workbook (options: English and Português). Not reproduced outside the portal; portal rendering not verified.
- **Português:** parâmetro Language sem `defaultValue` e sem `selected`, que parecem gerar a opção *Default items* com valor fora de EN/PT. Idioma inicial agora English (como no agent-support). Renderização no portal não verificada.

## 2.3.1 – 2026-11-10
- indexof in extension-to-host joins is now case-insensitive (indexof(tolower(id), '/extensions')) in 11 queries, matching the reconciliation workbook. The ESU hint in su_gap no longer hard-codes a date; dates moved to the guide with a Microsoft Learn source. Status icons (ArcStatus) and bars (Instances) added to grids. Portal rendering not verified.
- **Português:** indexof sem distinção de maiúsculas em 11 queries; dica de ESU sem data fixa (datas no guia, com fonte); ícones de status e barras nas grades. Renderização no portal não verificada.

## 2.3.0 – 2026-11-06
- **Core-capacity approximation:** Standard uses 24 cores through SQL Server 2022 and 32 for SQL Server 2025, based on the machine's Standard instances. Unknown editions/core counts are not reported as zero. Capacity is explicitly not a licensing requirement or billing meter.
- Per-host architecture recommendations no longer describe Standard capacity as a PAYG billing cap; VM and physical-host guidance is consistent with the estimate methodology in EN/PT.
- Host inventory/review queries preserve `id` for ARG pagination. Shared harness validates completeness, inherited visibility and multi-select subsets; deployment guides explain reusing the workbook GUID.
- **Português:** aproximação de capacidade Standard por versão; valores desconhecidos preservados; capacidade separada de cobrança/licenciamento também nas recomendações por host; `id` nas grades por host; validador e guias EN/PT atualizados. Fontes oficiais verificadas em 2026-11-06.

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
