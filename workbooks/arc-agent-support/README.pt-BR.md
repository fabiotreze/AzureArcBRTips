# Azure Arc – Conformidade de versão do Connected Machine Agent (Workbook)

[English](README.md) · [Português](README.pt-BR.md)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-agent-support-azuredeploy.json)

> ⚠️ **Projeto pessoal e independente – não é uma ferramenta oficial da Microsoft.** Fornecido no estado em que se encontra, sem garantia; veja o [aviso legal](../../DISCLAIMER.md#aviso-legal) do repositório. O status de suporte é uma **estimativa** (as APIs do Azure não expõem datas de release) – valide nas [release notes do agent](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes). O uso é de sua responsabilidade.

Workbook do Azure Monitor para servidores habilitados pelo Azure Arc. **Versão atual: 4.6.8** (veja o [CHANGELOG](CHANGELOG.md)). Responde três perguntas:

1. Meus **Connected Machine agents provavelmente estão dentro da janela de suporte e acima do mínimo configurado**?
2. O **upgrade automático do agent** está habilitado e funcionando?
3. **O que precisa ser corrigido** e em quais servidores?

O suporte é estimado por número de releases sequenciais, não por datas verificadas; estar acima do mínimo configurado não comprova a instalação de todas as correções de segurança. Nenhuma lista de versões fica fixa no código: a referência é lida do Azure em tempo real (alvo do upgrade automático, APIs de catálogo do Hybrid Compute, Resource Graph, Advisor, Policy). A API de listagem do catálogo não é determinística; por isso o workbook combina várias chamadas, nunca depende só dela e obtém os downloads pela versão exata. Interface bilíngue (English / Português). Somente leitura.

## Seções

| # | Seção | O que mostra |
|---|---|---|
| 1 | Visão geral | Aviso quando há servidores desconectados / expirados; tiles de *Situação da frota* e *Versão e upgrade* (Latest / Supported / Out of support / **Abaixo do piso de segurança** / upgrade automático); **Servidores que precisam de ação** com o motivo |
| 2 | Distribuição | Versões, status de conexão, saúde do upgrade automático (gráficos opcionais: *Mostrar gráficos de distribuição*, desligado por padrão) |
| 3 | Azure Advisor | Bloqueios (expirados / desconectados) e recomendações do agent, com link para os recursos afetados no Advisor e verificação de atualidade |
| 4 | Inventário | Uma linha por servidor (até 1000), abaixo do piso e fora de suporte primeiro |
| 5 | Upgrade automático | Elegibilidade (agent 1.67+), saúde (On track / Lagging / Failing / Blocked), última tentativa |
| 6 | Referência de latest e upgrade manual | Latest por SO e sua origem; próximo passo por versão instalada; download do agent pela versão exata (latest já selecionada) |
| 7 | Azure Policy | Apenas políticas do agent / upgrade automático, com mensagem explícita quando não há nenhuma atribuída |
| 8 | Extensões | Todas as extensões: cobertura de upgrade automático, versões vs. publicadas pelo Azure, problemas agrupados por causa com todos os servidores afetados |

Controles: *Mostrar guia* exibe a legenda, a metodologia e as fontes oficiais. *Exibir histórico* (modo Edit) mostra o histórico editorial dentro do workbook.

## Regras (editáveis no modo Edit)

| Parâmetro | Padrão | Significado |
|---|---|---|
| SupportWindow | 12 releases | Apenas heurística: aproxima a política oficial dos últimos 12 meses pelo número sequencial de releases; confirme as datas nas notas de versão do agent |
| AutoUpgradeTolerance | 1 | Heurística, não uma garantia documentada (a Microsoft libera os upgrades automáticos em lotes e repete as falhas); *On track* também exige conectividade e ausência de falha na última tentativa |
| MinAutoUpgradeVersion | 1.67 | O upgrade automático exige agent 1.67 ou superior (Windows: execution policy do PowerShell RemoteSigned; Linux: serviço cron) |
| **SecurityFloorVersion** | **1.61** | Mínimo configurável baseado em registros públicos de CVE (CVE-2026-26117 afeta agents < 1.61, CVE-2025-49692 < 1.49; CVE-2025-26627 e CVE-2025-55316 como no Arc Posture Review); aplicado a todos os SOs; estar acima dele **não** atesta segurança. Revise regularmente novas correções e esse limite |
| LatestOverride | 1.69 | Referência manual das notas de versão do agent. Quando preenchido, tem prioridade sobre todas as outras fontes (não é um máximo), mesmo que o Azure reporte uma versão maior: atualize ou limpe a cada release |

Sem override, *Latest* é a maior versão que o Azure reporta e pode ficar atrás da release mais recente.

## Deploy

- Botão **Deploy to Azure** acima → escolha assinatura / resource group → abra em *Azure Monitor → Workbooks*.
- **Azure CLI**: `az deployment group create -g <resource-group> --template-uri https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/main/templates/arc-agent-support-azuredeploy.json`
- **Manual**: Workbooks → New → *Advanced Editor* (`</>`) → cole [`arc-agent-support-workbook.json`](../arc-agent-support-workbook.json) → Apply → Save.

**Permissões:** Reader nas assinaturas / management group para consultar os dados. Implantar o template ARM ou salvar o workbook exige permissões adicionais para implantar/criar ou atualizar o recurso de workbook. As consultas são somente leitura; a implantação cria um recurso.

## Validação

[`scripts/Test-ArcWorkbookQueries.ps1`](../../scripts/Test-ArcWorkbookQueries.ps1) lê o workbook, resolve os parâmetros como o portal faz e executa todas as queries de todas as abas no seu tenant (somente leitura). Informa, por query, status, linhas, duração, throttling HTTP 429 e truncamento. Exige PowerShell 7+, Az.Accounts, Az.ResourceGraph e Reader nas assinaturas. Execute a partir da raiz do repositório:

```powershell
Connect-AzAccount -Tenant <tenant-id>
# lint offline (sem chamada ao Azure)
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -DryRun
# cada valor de filtro isoladamente + os 3 primeiros detalhamentos de extensão
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Language PT -FilterCombos OneFactor -ExtensionDrill 3
# abre cada aba como o portal (todas as queries ao mesmo tempo) com os gráficos opcionais ligados – reproduz HTTP 429
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Burst -SetParam @{ ShowCharts = 'Yes' }
```

Os resultados vão para `./workbook-test-results` (excluído pelo `.gitignore`). Com os gráficos ligados, a aba Visão geral executa 10 queries do Resource Graph ao mesmo tempo; o script repete automaticamente um HTTP 429 ocasional.

Os valores de `-SetParam` são aplicados antes da resolução dos parâmetros dependentes. Falhas de consulta, tokens não resolvidos e falhas de parâmetro produzem código de saída **1**; sucesso produz **0**. As falhas de parâmetro aparecem no CSV e no resumo final em vermelho. Execute os testes de regressão offline com mocks usando `pwsh -NoProfile -File .\scripts\Test-ArcWorkbookQueries.Tests.ps1`.

Na execução normal, parâmetros que aguardam apenas valores exportados pela seleção de linha de uma consulta aparecem como **Skipped (aguarda seleção)** no CSV e no resumo, sem reprovar a execução. Os nomes exportados são descobertos pelos metadados das consultas. `-ExtensionDrill` fornece valores de seleção e valida as consultas dos parâmetros; uma falha real ou um token não resolvido que não venha da seleção continua produzindo código de saída **1**.

> Os relatórios de teste contêm dados do ambiente – trate como confidenciais e nunca anexe em issues ou commits.

## Relacionados

- [Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) – avaliação de segurança pontual; este workbook é a visão contínua da parte de agent/extensões.
- [Gerenciar versões do Connected Machine agent](https://learn.microsoft.com/azure/azure-arc/servers/manage-agent) · [Resolver recomendações do Advisor para servidores Arc](https://learn.microsoft.com/azure/azure-arc/servers/resolve-azure-advisor-recommendations)

Veja o [CHANGELOG](CHANGELOG.md).
