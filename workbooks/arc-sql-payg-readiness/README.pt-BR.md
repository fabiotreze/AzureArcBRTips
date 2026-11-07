# SQL Server habilitado pelo Azure Arc – Workbook de prontidão PAYG

Azure Workbook que mostra, em um só lugar, o quão prontas estão as suas **instâncias SQL Server habilitadas pelo Azure Arc** para o licenciamento **pay-as-you-go (PAYG)** e o que verificar antes e depois da transição.

> **Projeto pessoal e não oficial.** Não é um produto da Microsoft nem uma ferramenta oficial de licenciamento. Os números de núcleos são estimativas, não medidores. Confirme os direitos pelo seu processo de licenciamento e os valores no Cost Management. Veja o [DISCLAIMER](../../DISCLAIMER.md).

**Versão:** 2.3.0 · **Idiomas:** English / Português (troque no parâmetro *Language*) · **Modo:** somente leitura (Azure Resource Graph; nada é alterado no seu ambiente)

[English](README.md) · [Changelog](CHANGELOG.md) · Arquivo do workbook: [`arc-sql-payg-readiness-workbook.json`](../arc-sql-payg-readiness-workbook.json)

Para publicar, siga o [fluxo de registro de revisões](CHANGELOG.md#azure-revision-tracking). Registre a revisão atualmente publicada no Azure na nova linha editorial **antes** de salvar; o Azure gera a próxima revisão automaticamente. Publicar no GitHub, por si só, não atualiza um workbook implantado.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-sql-payg-readiness-azuredeploy.json)

## O que ele responde
- Quais instâncias SQL Server com Arc já são PAYG, quais não são e quais tipos de licença estão em uso (LicenseOnly, Paid, PAYG).
- O que o script oficial `manage-payg-transition.ps1` **converteria** e quais hosts precisam de atenção primeiro (prioridade 🔴 🟠 🟢).
- O que falta para uma transição segura: extensão SQL, lacuna de ESU (SQL Server 2014/2016), **consentimento CSP para cobrança PAYG recorrente**, conectividade (check-in com mais de 30 dias), alinhamento pCore x plano de cobrança, tags de implantação automática.
- Aproximação de capacidade de núcleos por host (mínimo 4; Standard 24 até SQL Server 2022 e 32 para 2025; edições gratuitas 0), preservando valores desconhecidos, e sinais de VM x físico. Não representa requisito de licenciamento nem medidor de cobrança.

Os limites Standard descrevem a [capacidade computacional do mecanismo](https://learn.microsoft.com/sql/sql-server/compute-capacity-limits-by-edition-of-sql-server), não um teto universal de cobrança. Hosts mistos usam o limite das suas instâncias Standard, não a versão de uma instância Developer. Reconcilie o licenciamento de hosts físicos e VMs separadamente com o [Microsoft Learn](https://learn.microsoft.com/sql/sql-server/azure-arc/manage-license-billing) e o Cost Management. Verificado em 2026-11-06.

## Caminho rápido
1. **Resumo**: panorama, mix de licenças, versões, situação de suporte.
2. **Revisão PAYG**: comece pelos hosts 🔴; veja o que o script converteria.
3. **Validações**: ESU, consentimento CSP, conectividade, pCore.
4. Rode o script oficial com `-ReportOnly` e reconcilie.
5. Pilote um conjunto pequeno aprovado com `-WaitForCompletion`.
6. Confirme no Cost Management e defina a tag de implantação automática.

A aba *Como usar* tem botões que levam direto a cada aba e links para o script, o README e as páginas do Microsoft Learn.

## Abas
| Aba | Uso |
|---|---|
| Como usar | Objetivo, caminho rápido com links diretos, limites |
| Resumo | Tiles, mix de licenças, versões, situação de suporte |
| Revisão PAYG / exportações | Prioridade por host, o que o script converteria, próxima ação, pendências |
| Inventário completo / exportação | Evidências completas, exportáveis (grades até 10.000 linhas, com busca) |
| Arquitetura / dimensionamento | Sinal VM x físico, estimativa de núcleos, opções pCore e virtualização ilimitada |
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

Execute `-DryRun`, modo normal e `-Burst` nos dois idiomas, com escopo explícito em `-Subscriptions <subscription-id>`. Teste também todas as abas e botões do caminho rápido no portal; testes de API não verificam renderização nem navegação.

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
