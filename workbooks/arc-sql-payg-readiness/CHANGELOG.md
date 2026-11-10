# Changelog – SQL Server enabled by Azure Arc – PAYG Readiness Workbook

## 2.4.7 – 2026-11-11
- **Validation:** the *PAYG change history* table now also lists property changes of the `SQLServerLicense` resource (physical core license scenario, for example `billingPlan` Paid to PAYG), with a *Kind* column (SQL extension or SQLServerLicense); the create/delete table is limited to Create and Delete records. No new query (Validation tab stays at 10). Which license property names appear in `resourcechanges` is not verified; portal rendering not verified.
- **Português:** Validações: a tabela *Histórico de mudanças PAYG* agora também lista mudanças de propriedades do recurso `SQLServerLicense` (cenário de licença de núcleos físicos, por exemplo `billingPlan` de Paid para PAYG), com coluna *Kind* (Extensão SQL ou SQLServerLicense); a tabela de criação/exclusão ficou limitada a registros Create e Delete. Nenhuma consulta nova (a aba Validações continua com 10). Quais nomes de propriedade da licença aparecem no `resourcechanges` não foi verificado; renderização no portal não verificada.

## 2.4.6 – 2026-11-11
- **Validation:** new section *PAYG change history* based on the ARG `resourcechanges` table ([Learn](https://learn.microsoft.com/azure/governance/resource-graph/changes/get-resource-changes), checked 2026-11-10). One table lists changes of the SQL extension settings `LicenseType`, `UsePhysicalCoreLicense`, ESU and recurring consent (before and after, who, client); another lists creation and deletion of the SQL extension and `SQLServerLicense`. This gives a before/after view inside the workbook for recent changes. Two read-only queries (Validation tab now has 10). The retention window is not verified (about 10 days seen in one lab); a new property is not listed as a change and deleted resources have no snapshot. Guided step 8 points to the section. Queries not yet run in the portal by me; rendering not verified.
- **Português:** Validações: nova seção *Histórico de mudanças PAYG* baseada na tabela `resourcechanges` do ARG ([Learn](https://learn.microsoft.com/azure/governance/resource-graph/changes/get-resource-changes), consultado em 10/11/2026). Uma tabela lista mudanças das configurações da extensão SQL `LicenseType`, `UsePhysicalCoreLicense`, ESU e consentimento recorrente (antes e depois, quem, cliente); outra lista criação e exclusão da extensão SQL e de `SQLServerLicense`. Dá uma visão antes/depois dentro do workbook para mudanças recentes. Duas consultas somente leitura (a aba Validações agora tem 10). A janela de retenção não foi verificada (cerca de 10 dias vistos em um lab); propriedade nova não aparece como mudança e recursos excluídos não têm snapshot. O passo 8 do guia aponta para a seção. Consultas ainda não executadas por mim no portal; renderização não verificada.

## 2.4.5 – 2026-11-11
- **How to use (text and buttons only):** the quick path is now an 8-step guided path (scope, baseline, fix the base, triage, cores, prerequisites, script dry run, pilot). Each step says where to look, what to do and when it is done; the buttons follow the steps. The priority text now includes hosts without an Arc machine in ARG and the tab table lists *SQL on Azure VMs*. No query changed. Portal rendering and button navigation not verified.
- **Português:** Como usar (somente texto e botões): o caminho rápido virou um caminho guiado de 8 passos (escopo, linha de base, corrigir a base, triagem, núcleos, pré-requisitos, simulação do script, piloto). Cada passo diz onde olhar, o que fazer e quando está pronto; os botões seguem os passos. O texto de prioridade inclui hosts sem máquina Arc no ARG e a tabela de abas lista *SQL em VMs Azure*. Nenhuma consulta alterada. Renderização no portal e navegação dos botões não verificadas.

## 2.4.4 – 2026-11-11
- **Summary/Inventory:** new tile *Hosts with Arc machine in ARG*; the tile *No Arc machine in ARG* is now *Instance without Arc machine (stale?)*. The Inventory adds *LastInstanceInventory* (instance `lastInventoryUploadTime`) and the flag *No Arc machine (stale instance?)*. Observed in the lab on 2026-11-10: for an instance whose machine is not in ARG, the portal says the Arc machine resource was not found, yet mode shows `Connected` with an old upload date, so that `Connected` is not reliable. In two lab subscriptions 5 of 11 and 54 of 84 hosts had no machine in ARG (same subscription, not found by name either). The cause (for example a deleted machine) and billing behavior are not verified in Microsoft Learn. Portal rendering not verified.
- **Português:** Resumo/Inventário: novo bloco *Hosts com máquina Arc no ARG*; o bloco *Sem máquina Arc no ARG* agora é *Instância sem máquina Arc (residual?)*. O Inventário ganha *LastInstanceInventory* (`lastInventoryUploadTime` da instância) e o sinal *Sem máquina Arc (instância residual?)*. Observado no lab em 10/11/2026: numa instância cuja máquina não está no ARG, o portal informa que o recurso da máquina Arc não foi encontrado, mas o modo mostra `Connected` com data antiga de carga; esse `Connected` não é confiável. Em duas assinaturas do lab, 5 de 11 e 54 de 84 hosts não tinham máquina no ARG (mesma assinatura, também não achada por nome). A causa (por exemplo, máquina excluída) e o comportamento de cobrança não foram verificados na Microsoft Learn. Renderização no portal não verificada.
## 2.4.3 – 2026-11-11
- **Summary:** the *Arc not connected* tile counted hosts whose Arc machine is absent from Azure Resource Graph (empty status is "not Connected"), which inflated it (61 in the lab). It now counts only hosts with an Arc machine whose status is not Connected. New tile *No Arc machine in ARG*; *Arc SQL hosts* renamed *Hosts with SQL instances* (it always included hosts without a visible machine). The Inventory note now describes rows without an Arc machine and where to validate them. The lab split after the change is not verified; portal rendering not verified.
- **Português:** Resumo: o bloco *Arc desconectado* contava hosts sem máquina Arc no ARG (status vazio é "não Connected"), inflando o número (61 no lab). Agora conta só hosts com máquina Arc cujo status não é Connected. Novo bloco *Sem máquina Arc no ARG*; *Hosts Arc SQL* renomeado para *Hosts com instância SQL*. A nota do Inventário descreve as linhas sem máquina Arc e onde validá-las. A divisão no lab após a mudança não foi verificada; renderização no portal não verificada.

## 2.4.2 – 2026-11-10
- **SQL on Azure VMs tab:** the values `NotSet` (license type) and `Unknown` (edition), returned by the API in the lab tenant but not listed in the 2023-10-01 spec enum, are now shown as "Not reported" in the summary and review list; the tab note says so. Verified live: 28 SQL VMs returned in the lab, 4 of them with `NotSet`/`Unknown`. Portal rendering of the change not verified.
- **Português:** aba SQL em VMs Azure: `NotSet` (licença) e `Unknown` (edição), retornados pela API no lab mas fora do enum do spec 2023-10-01, agora aparecem como "Not reported" no resumo e na lista; a nota informa isso. Verificado ao vivo: 28 SQL VMs no lab, 4 com `NotSet`/`Unknown`. Renderização no portal da mudança não verificada.

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
