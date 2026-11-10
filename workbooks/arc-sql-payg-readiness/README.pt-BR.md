# SQL Server habilitado pelo Azure Arc – Workbook de prontidão PAYG

Azure Workbook que mostra, em um só lugar, o quão prontas estão as suas **instâncias SQL Server habilitadas pelo Azure Arc** para o licenciamento **pay-as-you-go (PAYG)** e o que verificar antes e depois da transição.

> **Projeto pessoal e não oficial.** Não é um produto da Microsoft nem uma ferramenta oficial de licenciamento. Os números de núcleos são estimativas, não medidores. Confirme os direitos pelo seu processo de licenciamento e os valores no Cost Management. Veja o [DISCLAIMER](../../DISCLAIMER.md).

**Versão:** 2.4.5 · **Idiomas:** English / Português (troque no parâmetro *Language*) · **Modo:** consultas somente leitura (Azure Resource Graph); implantar ou salvar cria ou atualiza um recurso de workbook, sem alterar os servidores inventariados ou seu licenciamento.

[English](README.md) · [Changelog](CHANGELOG.md) · Arquivo do workbook: [`arc-sql-payg-readiness-workbook.json`](../arc-sql-payg-readiness-workbook.json)

Para publicar, siga o [fluxo de registro de revisões](CHANGELOG.md#azure-revision-tracking). Registre a revisão atualmente publicada no Azure na nova linha editorial **antes** de salvar; o Azure gera a próxima revisão automaticamente. Publicar no GitHub, por si só, não atualiza um workbook implantado.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-sql-payg-readiness-azuredeploy.json)

## O que ele responde
- Quais instâncias SQL Server com Arc já são PAYG, quais não são e quais tipos de licença estão em uso (LicenseOnly, Paid, PAYG).
- O que o script oficial `manage-payg-transition.ps1` **converteria** e quais hosts precisam de atenção primeiro (prioridade 🔴 🟠 🟢).
- O que falta para uma transição segura: extensão SQL, lacuna de ESU (SQL Server 2014/2016), **consentimento CSP para cobrança PAYG recorrente**, conectividade (check-in com mais de 30 dias), alinhamento pCore x plano de cobrança, tags de implantação automática.
- Aproximação de capacidade de núcleos por host (mínimo 4; Standard 24 até SQL Server 2022 e 32 para 2025; edições gratuitas 0), preservando valores desconhecidos, e sinais de VM x físico. Não representa requisito de licenciamento nem medidor de cobrança.

Os limites Standard descrevem a [capacidade computacional do mecanismo](https://learn.microsoft.com/sql/sql-server/compute-capacity-limits-by-edition-of-sql-server), não um teto universal de cobrança. Hosts mistos usam o limite das suas instâncias Standard, não a versão de uma instância Developer. Reconcilie o licenciamento de hosts físicos e VMs separadamente com o [Microsoft Learn](https://learn.microsoft.com/sql/sql-server/azure-arc/manage-license-billing) e o Cost Management. Verificado em 2026-11-06.

## Caminho guiado (8 passos)
1. **Escopo**: selecione as assinaturas.
2. **Linha de base** (Resumo): hosts com instância SQL x hosts com máquina Arc no ARG, Arc desconectado, mix de licenças, hosts 🔴.
3. **Corrigir a base** (Inventário, Validações): hosts sem máquina Arc, agentes desconectados, extensão ausente.
4. **Triagem** (Revisão PAYG): 🔴 e depois 🟠; decida quais hosts excluir.
5. **Núcleos** (Arquitetura): VM x físico, estimativa de núcleos, pCore.
6. **Pré-requisitos** (Validações): ESU, consentimento CSP, tags, SQLServerLicense, pCore.
7. **Simulação**: script oficial com `-ReportOnly`, comparado com *Script selecionaria (ARG)*.
8. **Piloto e confirmação**: `-WaitForCompletion` em um conjunto pequeno, Cost Management, tag de auto-deploy.

A aba *Como usar* explica cada passo (onde olhar, o que fazer, quando está pronto) e tem botões que levam a cada aba e links para o script e as páginas do Microsoft Learn.

## Abas
| Aba | Uso |
|---|---|
| Como usar | Objetivo, caminho guiado de 8 passos com links diretos, limites |
| Resumo | Tiles (hosts com instância SQL, hosts com máquina Arc no ARG, instâncias sem máquina Arc (possivelmente residuais), Arc desconectado, mix de licenças), versões, situação de suporte |
| Revisão PAYG / exportações | Prioridade por host, o que o script converteria, próxima ação, pendências |
| Inventário completo / exportação | Evidências completas, exportáveis (grades até 10.000 linhas, com busca) |
| Arquitetura / dimensionamento | Sinal VM x físico, estimativa de núcleos, opções pCore e virtualização ilimitada |
| SQL em VMs Azure | `Microsoft.SqlVirtualMachine` (VMs do Azure, não Arc): tipo de licença PAYG / AHUB / DR por edição, lista de revisão das edições pagas. Software Assurance e vCores não são visíveis; DR é a réplica HA/DR gratuita; `NotSet` e `Unknown` retornados pela API aparecem como Not reported. Fontes: [modelo de licença](https://learn.microsoft.com/azure/azure-sql/virtual-machines/windows/licensing-model-azure-hybrid-benefit-ahb-change) e spec de API 2023-10-01 (verificado em 10/11/2026); renderização no portal não verificada |
| Validações | ESU, consentimento CSP, conectividade, pCore, tags de implantação, extensão ausente |
| Referências | Documentação oficial utilizada |

## Requisitos
- Azure Reader (ou superior) nas assinaturas selecionadas.
- Acesso ao Azure Resource Graph. O workbook não exige outro provedor de recursos nem agente.
- Servidores e instâncias SQL já integrados ao Azure Arc com a extensão do SQL Server.

## Importação
1. Portal do Azure → **Monitor** (ou **Azure Arc**) → **Workbooks** → **Novo**.
2. Abra o **Editor avançado** (`</>`), escolha **Modelo da galeria**, cole o conteúdo de [`arc-sql-payg-readiness-workbook.json`](../arc-sql-payg-readiness-workbook.json) e selecione **Aplicar**.
3. Selecione **Salvar**, escolha a assinatura, o grupo de recursos e a região.

Para **atualizar via ARM**, reutilize o GUID do recurso existente:

```azurecli
az deployment group create --resource-group <resource-group> --template-file templates/arc-sql-payg-readiness-azuredeploy.json --parameters workbookId=<existing-workbook-guid>
```

Se omitido, o padrão `newGuid()` cria outro workbook; veja o [comportamento ARM](https://learn.microsoft.com/azure/azure-resource-manager/templates/template-functions-string#newguid) (verificado em 2026-11-06). Faça backup do recurso atual antes de atualizar. Para reproduzir implantações com templates remotos, substitua `main` pelo SHA do commit revisado. Preserve o template anterior e o mesmo GUID para rollback.

## Validação realizada
- 18 queries do Azure Resource Graph executadas em um tenant de teste em português e inglês: **18/18 OK, 0 falhas**.
- Throttling: cada aba executa no máximo 8 queries (o Azure Resource Graph permite cerca de 15 a cada 5 segundos por usuário). Um teste de estresse trocando de aba em sequência gerou algumas respostas HTTP 429 que se recuperaram na nova tentativa.
- Scripts de teste: [`scripts/Test-ArcWorkbookQueries.ps1`](../../scripts/Test-ArcWorkbookQueries.ps1).
- O validador aplica `-SetParam` antes da resolução dos parâmetros dependentes e termina com **1** para falhas de consulta, tokens não resolvidos ou falhas de parâmetro; caso contrário, **0**. As falhas de parâmetro aparecem no CSV e no resumo final em vermelho. Testes de regressão offline com mocks: `pwsh -NoProfile -File .\scripts\Test-ArcWorkbookQueries.Tests.ps1` (a partir da raiz do repositório).
- Parâmetros que aguardam apenas valores exportados pela seleção de linha de consultas aparecem como **Skipped (aguarda seleção)**, sem reprovar a execução normal; os nomes exportados são descobertos pelos metadados das consultas. A validação de drill-down continua rigorosa, e tokens não resolvidos que não venham da seleção continuam reprovando a execução.
- Um laboratório pequeno não comprova o comportamento em escala. Valide no seu ambiente antes de usar os resultados em decisões.

O validador usa metadados REST de paginação do ARG; resultados **INCOMPLETE** reprovam a validação, inclusive em Burst. Consultas de inventário/revisão por host preservam `id` para tokens de continuação. Configurar a grade para 10.000 linhas não garante que a fonte retornou todos os registros. Veja [paginação ARG](https://learn.microsoft.com/azure/governance/resource-graph/concepts/work-with-data) e [limites de workbooks](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-limits) (verificado em 2026-11-06).

Execute `-DryRun`, modo normal e `-Burst` nos dois idiomas, com escopo explícito em `-Subscriptions <subscription-id>`. Teste também todas as abas e botões do caminho guiado no portal; testes de API não verificam renderização nem navegação.

## Documentação oficial
- [Gerenciar licença e cobrança do SQL Server](https://learn.microsoft.com/sql/sql-server/azure-arc/manage-license-billing)
- [Transição para pay-as-you-go](https://learn.microsoft.com/sql/sql-server/azure-arc/manage-pay-as-you-go-transition)
- [Implantação automática da extensão do SQL Server](https://learn.microsoft.com/sql/sql-server/azure-arc/manage-autodeploy)
- [Gerenciar o tipo de licença em escala](https://learn.microsoft.com/sql/sql-server/manage-license-type-at-scale)
- [Extended Security Updates](https://learn.microsoft.com/sql/sql-server/azure-arc/extended-security-updates)
- [`manage-payg-transition.ps1` (sql-server-samples)](https://github.com/microsoft/sql-server-samples/blob/e1163bff690ef8b3109d83dd139ffdf1a40219da/samples/manage/manage-payg-transition/manage-payg-transition.ps1)

## Limites conhecidos
- A coluna "O script converteria?" é uma aproximação de uma versão fixa do script (commit `e1163bf`). Releia o script antes de executá-lo.
- O workbook não enxerga direitos (Software Assurance), cobrança nem contratos CSP.
- As dicas de ESU na grade não trazem datas. Segundo as páginas de ciclo de vida do Microsoft Learn (verificado em 10/11/2026), o suporte estendido terminou para o [SQL Server 2014](https://learn.microsoft.com/lifecycle/products/sql-server-2014) em 09/07/2024 e para o [SQL Server 2016](https://learn.microsoft.com/lifecycle/products/sql-server-2016) em 14/07/2026; os limites dos anos de ESU não foram verificados aqui.
- As chaves de `settings` da extensão `enableExtendedSecurityUpdates`, `UsePhysicalCoreLicense.IsApplied` e `ConsentToRecurringPAYG.Consented`/`ConsentTimestamp` são livres no spec do ARM, então a checagem de contrato não consegue validá-las. Nomes e caixa conferem com o [`modify-arc-sql-license-type.ps1` oficial](https://github.com/microsoft/sql-server-samples/blob/master/samples/manage/azure-arc-enabled-sql-server/modify-license-type/modify-arc-sql-license-type.ps1) (verificado em 10/11/2026). No laboratório do autor nenhuma das três estava preenchida, então as colunas mostram "não reportado" e não foram observadas com valores reais.- O Azure Resource Graph retorna no máximo 1.000 registros por chamada por padrão ([Learn](https://learn.microsoft.com/azure/governance/resource-graph/concepts/work-with-data)); não foi verificado se a grade do Workbooks pagina além disso com o limite de 10.000 linhas. Confirme em ambientes grandes.
