# SQL Server habilitado pelo Azure Arc – Workbook de prontidão PAYG

Azure Workbook que mostra, em um só lugar, o quão prontas estão as suas **instâncias SQL Server habilitadas pelo Azure Arc** para o licenciamento **pay-as-you-go (PAYG)** e o que verificar antes e depois da transição.

> **Projeto pessoal e não oficial.** Não é um produto da Microsoft nem uma ferramenta oficial de licenciamento. Os números de núcleos são estimativas, não medidores. Confirme os direitos pelo seu processo de licenciamento e os valores no Cost Management. Veja o [DISCLAIMER](../../DISCLAIMER.md).

**Versão:** 2.2.2 · **Idiomas:** English / Português (troque no parâmetro *Language*) · **Modo:** somente leitura (Azure Resource Graph; nada é alterado no seu ambiente)

[English](README.md) · [Changelog](CHANGELOG.md) · Arquivo do workbook: [`arc-sql-payg-readiness-workbook.json`](../arc-sql-payg-readiness-workbook.json)

[!\[Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-sql-payg-readiness-azuredeploy.json)

## O que ele responde
- Quais instâncias SQL Server com Arc já são PAYG, quais não são e quais tipos de licença estão em uso (LicenseOnly, Paid, PAYG).
- O que o script oficial `manage-payg-transition.ps1` **converteria** e quais hosts precisam de atenção primeiro (prioridade 🔴 🟠 🟢).
- O que falta para uma transição segura: extensão SQL, lacuna de ESU (SQL Server 2014/2016), **consentimento CSP para cobrança PAYG recorrente**, conectividade (check-in com mais de 30 dias), alinhamento pCore x plano de cobrança, tags de implantação automática.
- Estimativa de núcleos por instância (por OSE: mínimo 4, Standard máximo 24, edições gratuitas 0) e sinais de VM x físico.

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

## Validação realizada
- 18 queries do Azure Resource Graph executadas em um tenant de teste em português e inglês: **18/18 OK, 0 falhas**.
- Throttling: cada aba executa no máximo 8 queries (o Azure Resource Graph permite cerca de 15 a cada 5 segundos por usuário). Um teste de estresse trocando de aba em sequência gerou algumas respostas HTTP 429 que se recuperaram na nova tentativa.
- Scripts de teste: [`scripts/Test-ArcWorkbookQueries.ps1`](../../scripts/Test-ArcWorkbookQueries.ps1).
- Um laboratório pequeno não comprova o comportamento em escala. Valide no seu ambiente antes de usar os resultados em decisões.

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
