# Changelog - Azure Arc SQL Resource Reconciliation

Personal, independent project; see [DISCLAIMER](../../DISCLAIMER.md). Projeto pessoal e independente; veja o [aviso legal](../../DISCLAIMER.md#aviso-legal).

## 1.2.7 - 2026-11-10

- The `finding` text and the `rpValidation` value (`Pending`) in the exception queries now follow the *Language* parameter; they were always English (category codes are unchanged). Portal rendering not verified.
- **Português:** os textos de `finding` e o valor de `rpValidation` (`Pendente`) das consultas de exceção agora seguem o parâmetro *Language*; antes eram sempre em inglês (códigos de categoria inalterados). Renderização no portal não verificada.

## 1.2.6 - 2026-11-10

- License exceptions query: removed `properties.provisioningState` and `properties.state`, which are not in the Microsoft.AzureArcData `SqlServerLicense` / `SqlServerEsuLicense` API specs (checked with `scripts/Test-ArcWorkbookContract.ps1`). ESU licenses are now flagged when `activationState` is not Active (documented values: Inactive, Active, Terminated). The `status` and `provisioningState` columns were removed. Portal rendering not verified.
- **Português:** Consulta de exceções de licença: removidas `properties.provisioningState` e `properties.state`, que não constam nos specs de `SqlServerLicense` / `SqlServerEsuLicense` (verificado com `scripts/Test-ArcWorkbookContract.ps1`). Licenças ESU passam a ser sinalizadas quando `activationState` não é Active (valores documentados: Inactive, Active, Terminated). Colunas `status` e `provisioningState` removidas. Renderização no portal não verificada.

## 1.2.5 - 2026-11-10

- No query changed. The Language parameter now opens in English, like the other workbooks (Português stays available). The in-workbook banner showed 1.2.3; it now shows the real version. Portal rendering not verified.
- **Português:** Nenhuma query alterada. O parâmetro Language agora abre em English, como os outros workbooks (Português continua disponível). O banner dentro do workbook mostrava 1.2.3; agora mostra a versão real. Renderização no portal não verificada.

## 1.2.4 - 2026-11-10

- No query changed. All grids now offer Export to Excel and show a status icon in the severity column. Portal rendering not verified.
- **Português:** Nenhuma query alterada. Todas as grades oferecem exportação para Excel e ícone de status na coluna severity. Renderização no portal não verificada.

## 1.2.3 - 2026-11-06

- Connectivity: extension health no longer flags plugin or component statuses ("status":"Error...") inside a message that is otherwise Healthy with upload OK; in a real run this flagged hosts that were healthy overall. Provisioning, non-Healthy status and upload failures are still reported.
- **Português:** Conectividade: a saúde da extensão não sinaliza mais status de plugin/componente em mensagem Healthy com upload OK (ruído em hosts saudáveis). Provisionamento, status não Healthy e falha de upload continuam reportados.

## 1.2.2 - 2026-11-06

- Connectivity: removed the stale-inventory check and its threshold parameter. In a real run, instances with status Connected on hosts with a healthy extension showed old inventory timestamps (cause not verified), so the check produced false positives. The instance status check remains; the inventory timestamp is shown for context only.
- **Português:** Conectividade: removida a verificação de inventário antigo e seu parâmetro de limite (falsos positivos em instâncias Connected com extensão saudável; causa não verificada). A verificação de status da instância permanece; o horário do inventário é só contexto.

## 1.2.1 - 2026-11-06

- FCI: new queries for a host declared by the consolidated projection without a node projection (observed in the lab) and a node projection whose container is not among the declared hosts (host names compared without domain suffix; heuristic).
- Connectivity: new query for instances that remain while their existing Arc machine has no SQL extension.
- EN/PT guides: new diagram limited to Arc machine plus SQL extension, classification table and direct-provider validation outcomes, updated scenario coverage.
- All fifteen queries executed in a lab subscription without error; portal rendering and positive cases for the extension and node-container queries remain not verified.
- **Português:** FCI: host declarado sem projeção de nó e projeção de nó não declarada; Conectividade: instância sem extensão no host; novo diagrama, tabela de classificação e resultados de validação nos guias. Quinze queries executadas em laboratório; renderização no portal e casos positivos de extensão ausente e nó/contêiner não verificados.

## 1.2.0 - 2026-11-06

- Orphan detection: databases and availability groups are now flagged when their parent instance exists but its Arc machine is absent from ARG (transitive orphans), or the instance has no container. Instance-to-container rows show inventory age.
- Match both `WindowsAgent.SqlServer` and `LinuxAgent.SqlServer` extensions.
- New **Connectivity** tab with a stale-inventory threshold parameter (default 30 days): instance status other than Connected, stale or missing inventory, and SQL extension provisioning/health/upload/plugin errors (message-format heuristic).
- Database-host query exposes whether an agent proxy URL is configured (boolean only). Connection mode is not judged as an exception.
- Add scenario coverage table (with verified/not verified status) to the EN/PT guides.
- All twelve queries executed without error in a lab subscription (PT and EN); this checks syntax and scope, not behavior on other topologies. Portal rendering remains not verified.
- **Português:** órfãos transitivos (bancos/AGs de instâncias sem máquina Arc), extensão Linux, nova aba Conectividade com limite de inventário antigo, tabela de cobertura de cenários. Doze queries executadas sem erro em assinatura de laboratório; renderização no portal não verificada.

## 1.1.0 - 2026-11-06

- Add a Relationships query for databases whose parent SQL instance runs on an Arc machine that is not Connected or lacks a Succeeded SQL extension; one row per SQL instance with database count and up to five sample names.
- Add a resource-model diagram and a finding-to-query table to the EN/PT guides.
- Query execution and portal rendering in the target environment remain not verified.
- **Português:** nova query em Relacionamentos para bancos cuja instância SQL está em máquina Arc fora de Connected ou sem extensão SQL Succeeded (uma linha por instância); diagrama do modelo de recursos e tabela achado-consulta nos guias EN/PT. Execução e renderização no ambiente-alvo não verificadas.

## 1.0.0 - 2026-11-06

- Initial repository integration with project guides EN/PT, generated ARM template and bilingual root catalog entry.
- Nine exception queries across four query tabs plus a validation guide; no full healthy inventory.
- Exclude known Azure VM containers while retaining unresolved parent candidates; match SQL extensions by publisher/type rather than resource name.
- Filter healthy FCI/AG summaries; preserve missing status metadata; correlate AG projections by ID rather than display name, keeping missing IDs separate.
- License resources only appear for incomplete SQL license fields or explicit non-Succeeded provisioning; no entitlement or billing conclusions.
- JSON and offline parameter/navigation checks performed locally. Target-environment query execution, positive/negative cases and portal navigation remain not verified.
- **Português:** integração inicial com guias EN/PT, template e catálogo; nove queries de exceção; escopo Arc; correlação AG por ID; metadados desconhecidos preservados; licenças sem conclusões de cobrança/direitos. Validação local; execução, casos positivos/negativos e navegação no ambiente-alvo não verificados.
