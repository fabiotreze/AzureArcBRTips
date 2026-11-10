# Azure Arc – Conformidade de versão do Connected Machine Agent (Workbook)

> ⚠️ **Projeto pessoal e independente – não é uma ferramenta oficial da Microsoft.** Fornecido no estado em que se encontra, sem garantia; veja o [aviso legal](../../DISCLAIMER.md#aviso-legal) do repositório. O status de suporte é uma **estimativa** (as APIs do Azure não expõem datas de release) – valide nas [release notes do agent](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes). O uso é de sua responsabilidade.

**Versão atual: 4.9.0** · **Idiomas:** English / Português · **Modo:** consultas somente leitura; implantar ou salvar cria ou atualiza um recurso de workbook, sem atualizar agents ou alterar os servidores inventariados.

[English](README.md) · [Português](README.pt-BR.md) · [Changelog](CHANGELOG.md) · Arquivo do workbook: [`arc-agent-support-workbook.json`](../arc-agent-support-workbook.json)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-agent-support-azuredeploy.json)

## O que ele responde

Workbook do Azure Monitor para servidores habilitados pelo Azure Arc. Responde três perguntas:

1. Meus **Connected Machine agents provavelmente estão dentro da janela de suporte e acima do mínimo configurado**?
2. O **upgrade automático do agent** está habilitado e funcionando?
3. **O que precisa ser corrigido** e em quais servidores?

O suporte é estimado por número de releases sequenciais, não por datas verificadas; estar acima do mínimo configurado não comprova a instalação de todas as correções de segurança. A referência é lida do Azure em tempo real (alvo do upgrade automático e endpoint exato `latest` do Hybrid Compute), respeitando o override manual explícito abaixo. A listagem paginada instável de agents não é usada. Downloads consultam a versão exata; o override opcional de download Windows/Linux não altera a conformidade. Não se promete catálogo completo de releases.

## Caminho rápido

1. Selecione assinaturas, idioma e filtros.
2. Abra **Visão geral** e revise os servidores que precisam de ação.
3. Use **Inventário** e **Upgrade automático** para examinar as evidências.
4. Revise **Referência de latest e upgrade manual**, **Advisor**, **Policy** ou **Extensões** conforme necessário.
5. Valide as recomendações nas fontes oficiais antes de fazer alterações fora do workbook.

## Abas

| # | Seção | O que mostra |
|---|---|---|
| 1 | Visão geral | Aviso quando há servidores desconectados / expirados; tiles de *Situação da frota* e *Versão e upgrade* (Latest / Supported / Out of support / **Abaixo do piso de segurança** / upgrade automático); **Servidores que precisam de ação** com o motivo (desconectado/expirado, abaixo do piso de segurança, fora de suporte, upgrade com falha/atrasado, upgrade manual necessário). Servidores que só têm upgrade automático desativado mas elegíveis aparecem como recomendação no bloco *Elegível, não ativado* e não entram em *Precisam de ação* |
| 2 | Distribuição | Versões, status de conexão, saúde do upgrade automático (gráficos opcionais: *Mostrar gráficos de distribuição*, desligado por padrão) |
| 3 | Azure Advisor | Bloqueios (expirados / desconectados) e recomendações do agent, com link para os recursos afetados no Advisor e verificação de atualidade |
| 4 | Inventário | Uma linha por servidor (até 1000), abaixo do piso e fora de suporte primeiro |
| 5 | Upgrade automático | Elegibilidade (agent 1.67+), saúde (On track / Lagging / Failing / Blocked), última tentativa |
| 6 | Referência de latest e upgrade manual | Latest por SO e sua origem; próximo passo por versão instalada; download do agent pela versão exata (latest já selecionada) |
| 7 | Azure Policy | Apenas políticas do agent / upgrade automático, com mensagem explícita quando não há nenhuma atribuída |
| 8 | Extensões | Extensões por publisher, tipo e região: cobertura de upgrade automático, versões vs. catálogo regional do Azure, problemas agrupados por causa |

Controles: *Mostrar guia* exibe a legenda, a metodologia e as fontes oficiais. *Exibir histórico* (modo Edit) mostra o histórico editorial dentro do workbook.

Os catálogos de extensões usam o array raiz combinado retornado por [ARM GETARRAY](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-data-sources#azure-resource-manager) (verificado em 2026-11-06). Sem versões retornadas, a comparação e a previsão de upgrade permanecem desconhecidas; installed-only não prova que uma versão foi retirada. Upgrade automático habilitado não garante rollout.

## Requisitos

Reader nas assinaturas / management group selecionados é necessário para consultar os dados. Implantar o template ARM ou salvar o workbook exige permissões adicionais para implantar/criar ou atualizar o recurso de workbook. Para validar as consultas, use PowerShell 7+ e Az.Accounts.

### Filtros e controles (parâmetros visíveis)

| Parâmetro | Padrão | Significado |
|---|---|---|
| Subscriptions | Todas | Assinaturas consultadas (Azure Resource Graph) |
| Language | EN | Seletor único EN / PT para todos os textos do workbook |
| OsFilter (OS) | Todos | Sistemas operacionais encontrados nas assinaturas selecionadas |
| StatusFilter (Connection Status) | Todos | Status de conexão encontrados nas assinaturas selecionadas |
| SupportFilter (Estimated support status) | Todos | Latest / Supported / Out of support / Unknown (heurística, veja Regras) |
| AutoUpgradeFilter (Auto Upgrade) | Todos | Enabled / Disabled / N/A |
| ShowInfo (Mostrar guia) | Não | Legenda, metodologia e fontes oficiais |
| ShowCharts (Mostrar gráficos de distribuição) | Não | Gráficos opcionais em Distribuição; abrir a aba executa 6 queries a mais |
| ShowChangelog (Exibir histórico) | Não | Histórico editorial (apenas modo Edit) |

Os demais parâmetros são ocultos: as *Regras* abaixo, as versões de API do Azure (`ApiVersion`, `ExtApiVersion`) e valores resolvidos pelo Azure (`ReleasedWindows`, `ReleasedLinux`, `LatestSummary`, `AnyOsTarget`, `SelectedTab`). Na aba Extensões, selecionar uma linha da primeira grade exporta `ExtPublisher`, `ExtType` e `ExtLocation` para as grades de comparação.

A consulta ao catálogo de extensões usa o caminho em nível de tenant, sem `/subscriptions/{id}`. Em 2026-11-10 ela retornou HTTP 200 com a mesma lista de versões do caminho documentado com a assinatura, para um publisher/tipo/região ([referência da API](https://learn.microsoft.com/rest/api/hybridcompute/extension-metadata-v-2/list)); outras regiões e publishers não foram testados.

### Regras (editáveis no modo Edit)

| Parâmetro | Padrão | Significado |
|---|---|---|
| SupportWindow | 12 releases | Apenas heurística: aproxima a política oficial dos últimos 12 meses pelo número sequencial de releases; confirme as datas nas notas de versão do agent (as [notas de versão](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes) indicam suporte apenas a versões lançadas no último ano; verificado em 2026-11-10) |
| AutoUpgradeTolerance | 1 | Heurística, não uma garantia documentada (a Microsoft libera os upgrades automáticos em lotes e repete as falhas); *On track* também exige conectividade e ausência de falha na última tentativa |
| MinAutoUpgradeVersion | 1.67 | O upgrade automático exige agent 1.67 ou superior (Windows: execution policy do PowerShell RemoteSigned; Linux: serviço cron) — [Learn](https://learn.microsoft.com/azure/azure-arc/servers/automatic-agent-upgrade), verificado em 2026-11-10 |
| **SecurityFloorVersion** | **1.61** | Mínimo configurável baseado em registros públicos de CVE (CVE-2026-26117 afeta agents < 1.61, CVE-2025-49692 < 1.49; CVE-2025-26627 e CVE-2025-55316 como no Arc Posture Review); aplicado a todos os SOs; estar acima dele **não** atesta segurança. Revise regularmente novas correções e esse limite. Registro do CVE-2026-26117 (afeta < 1.61) conferido em 2026-11-10; as notas da 1.70 listam correções de segurança sem faixa de versões afetadas, então o piso não foi elevado |
| LatestOverride | vazio | Referência manual opcional das notas de versão do agent. Quando preenchido, tem prioridade sobre todas as outras fontes (não é um máximo), mesmo que o Azure reporte uma versão maior: atualize ou limpe a cada release |

Sem override, a *Latest* é a maior entre a versão que o Azure reporta (`osType/agentVersions/latest`) e o alvo do upgrade automático visto na frota, e pode ficar atrás da release mais recente. Verificado em 2026-11-10: as notas de versão e o host de download já listavam a 1.70 (`Last-Modified` do host em 2026-11-09), enquanto a API ainda retornava a 1.69. Nenhuma fonte do Azure Resource Graph ou ARM informa a release mais recente de imediato, então não dá para remover a versão fixa sem aceitar esse atraso; preencha o *LatestOverride* temporariamente se precisar que a release mais nova seja considerada. O seletor de download pré-seleciona a versão confirmada pela API, então um override mais novo não gera 404.

## Importação

- Botão **Deploy to Azure** acima → escolha assinatura / resource group → abra em *Azure Monitor → Workbooks*.
- **Azure CLI**: `az deployment group create -g <resource-group> --template-uri https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/main/templates/arc-agent-support-azuredeploy.json`
- **Manual**: Workbooks → New → *Advanced Editor* (`</>`) → cole [`arc-agent-support-workbook.json`](../arc-agent-support-workbook.json) → Apply → Save.

Para **atualizar**, reutilize o GUID existente com `--parameters workbookId=<existing-workbook-guid>` no comando CLI. Sem ele, `newGuid()` é reavaliado e cria outro workbook. Para uma implantação reproduzível, substitua `main` na URL do template pelo SHA do commit revisado. Exporte o recurso existente antes de atualizar e guarde o backup para rollback. Veja o [comportamento de newGuid no ARM](https://learn.microsoft.com/azure/azure-resource-manager/templates/template-functions-string#newguid) (verificado em 2026-11-06).

Para publicar, siga o [fluxo de registro de revisões](CHANGELOG.md#azure-revision-tracking). Registre a revisão atualmente publicada no Azure na nova linha editorial **antes** de salvar; o Azure gera a próxima revisão automaticamente. Publicar no GitHub, por si só, não atualiza um workbook implantado.

## Validação

[`scripts/Test-ArcWorkbookQueries.ps1`](../../scripts/Test-ArcWorkbookQueries.ps1) resolve os tipos de parâmetros suportados pelo validador e executa as consultas visíveis de todas as abas no seu tenant (somente leitura). Avalia a visibilidade herdada dos grupos e informa status, linhas, duração, HTTP 429 e resultados incompletos. Usa a resposta REST do ARG para conferir metadados de paginação. Não substitui os testes de cliques no portal. Execute a partir da raiz do repositório:

```powershell
Connect-AzAccount -Tenant <tenant-id>
# lint offline (sem chamada ao Azure)
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -DryRun
# cada valor de filtro isoladamente + os 3 primeiros detalhamentos de extensão
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Language PT -FilterCombos OneFactor -ExtensionDrill 3
# abre cada aba como o portal (todas as queries ao mesmo tempo) com os gráficos opcionais ligados – reproduz HTTP 429
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Burst -SetParam @{ ShowCharts = 'Yes' }
# todos os subconjuntos nao vazios dos filtros e a selecao explicita All; consultas identicas executam uma vez por chamada
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Subscriptions <subscription-id> -Language EN -FilterCombos Subsets -CacheQueries -SetParam @{ ShowCharts = 'Yes' }
# cada linha de extensao/regiao e cada versao publicada oferecida na tabela de comparacao
./scripts/Test-ArcWorkbookQueries.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Subscriptions <subscription-id> -Language PT -ExtensionDrill 10000 -AllExtensionTargets -CacheQueries
```

Os resultados vão para `./workbook-test-results` (excluído pelo `.gitignore`). Com os gráficos ligados, a aba Visão geral executa 10 queries do Resource Graph ao mesmo tempo; o script repete automaticamente um HTTP 429 ocasional.

Repita os testes em **EN e PT**. `Subsets` cobre as opções enumeradas disponíveis naquela execução, não opções futuras nem todo texto livre. Teste os parâmetros de texto editáveis separadamente, com casos de borda documentados. `CacheHit=True` identifica a reutilização da consulta expandida idêntica e do mesmo escopo de assinaturas na execução; não use cache para medir latência de requisições repetidas nem throttling. Burst nunca utiliza esse cache.

Os valores de `-SetParam` são aplicados antes da resolução dos parâmetros dependentes. Falhas de consulta, tokens não resolvidos, falhas de parâmetro e resultados **INCOMPLETE** produzem código de saída **1**; sucesso produz **0**. A ausência de token de continuação não comprova completude. Exatamente 10.000 linhas só são completas se os metadados confirmarem que não há mais resultados. As falhas de parâmetro aparecem no CSV e no resumo final em vermelho. Execute os testes de regressão offline com mocks usando `pwsh -NoProfile -File .\scripts\Test-ArcWorkbookQueries.Tests.ps1`.

**Verificação de contrato com metadados (não testa resultados).** `pwsh -NoProfile -File .\scripts\Test-ArcWorkbookContract.ps1` compara cada caminho `properties.*`, tipo de recurso, tabela do Resource Graph e caminho ARM usados pelos workbooks com as fontes públicas: as especificações da API REST do Azure (`Azure/azure-rest-api-specs`) e a lista do Learn de tabelas suportadas do Resource Graph. `-Live` (somente leitura) também conta quantos recursos do seu tenant preenchem cada propriedade. Comprova que o workbook lê campos documentados; não comprova que as heurísticas (suportado, on track, precisa de ação) seguem a política da Microsoft. Propriedades de Advisor, política e assinatura aparecem como UNVERIFIED porque não há especificação comparada. Testes offline: `Test-ArcWorkbookContract.Tests.ps1`.

Na execução normal, parâmetros que aguardam apenas valores exportados pela seleção de linha de uma consulta aparecem como **Skipped (aguarda seleção)** no CSV e no resumo, sem reprovar a execução. Os nomes exportados são descobertos pelos metadados das consultas. `-ExtensionDrill` fornece valores de seleção e valida as consultas dos parâmetros; uma falha real ou um token não resolvido que não venha da seleção continua produzindo código de saída **1**.

> Os relatórios de teste contêm dados do ambiente – trate como confidenciais e nunca anexe em issues ou commits.

## Documentação oficial

- [Gerenciar versões do Connected Machine agent](https://learn.microsoft.com/azure/azure-arc/servers/manage-agent) · [Resolver recomendações do Advisor para servidores Arc](https://learn.microsoft.com/azure/azure-arc/servers/resolve-azure-advisor-recommendations)
- [Notas de versão do agent](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes)

## Limites conhecidos

As referências do agent usam consultas exatas a `latest`, e os downloads usam a versão exata `major.minor`. Deixe o override exclusivo de download vazio para usar a referência atual; uma versão indisponível produz erro da API. Os catálogos de extensões usam ARM `GETARRAY` para seguir a continuação, conforme a [documentação das fontes ARM de workbooks](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-data-sources#azure-resource-manager). As comparações de extensões preservam a região selecionada, seguindo a [API regional de metadados](https://learn.microsoft.com/rest/api/hybridcompute/extension-metadata-v-2/list). Verificado em 2026-11-06. As grades continuam limitadas a 1.000 linhas onde configurado; não são uma exportação ilimitada da frota.

## Manutenção

Após cada release do Connected Machine agent, consulte as [notas de versão do agent](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes) e atualize ou limpe o `LatestOverride` (veja Regras). Nenhum arquivo deste repositório acompanha datas de release.

## Projetos relacionados

- [Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) – avaliação de segurança pontual; este workbook é a visão contínua da parte de agent/extensões.

Veja o [CHANGELOG](CHANGELOG.md).
