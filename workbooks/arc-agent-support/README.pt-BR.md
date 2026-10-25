# Azure Arc – Conformidade de versão do Connected Machine Agent (Workbook)

[English](README.md) · [Português](README.pt-BR.md)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-agent-support-azuredeploy.json)

> ⚠️ **Projeto pessoal e independente – não é uma ferramenta oficial da Microsoft.** Fornecido no estado em que se encontra, sem garantia; veja o [disclaimer](../../README.md) do repositório. O status de suporte é uma **estimativa** (as APIs do Azure não expõem datas de release) – valide nas [release notes do agent](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes). O uso é de sua responsabilidade.

Workbook do Azure Monitor para servidores habilitados pelo Azure Arc. Responde três perguntas:

1. Meus **Connected Machine agents estão numa versão suportada – e segura**?
2. O **upgrade automático do agent** está habilitado e funcionando?
3. **O que precisa ser corrigido** e em quais servidores?

Nenhuma lista de versões fica fixa no código: a referência é lida do Azure em tempo real (alvo do upgrade automático, APIs de catálogo do Hybrid Compute, Resource Graph, Advisor, Policy). Interface bilíngue (English / Português). Somente leitura.

## Seções

| # | Seção | O que mostra |
|---|---|---|
| 1 | Visão geral | Latest / Supported / Out of support / Unknown / **Abaixo do piso de segurança**, conectividade, upgrade automático |
| 2 | Distribuição | Versões, status de conexão, saúde do upgrade automático |
| 3 | Azure Advisor | Bloqueios (expirados / desconectados) e recomendações do agent, com verificação de atualidade |
| 4 | Inventário | Uma linha por servidor, abaixo do piso e fora de suporte primeiro |
| 5 | Upgrade automático | Elegibilidade, saúde (On track / Lagging / Failing / Blocked), última tentativa |
| 6 | Referência de latest e upgrade manual | Latest por SO e sua origem; próximo passo e download por versão instalada |
| 7 | Azure Policy | Conformidade de políticas dos servidores Arc |
| 8 | Extensões | Todas as extensões: cobertura de upgrade automático, versões vs. publicadas pelo Azure, problemas agrupados por causa |

## Regras (editáveis no modo Edit)

| Parâmetro | Padrão | Significado |
|---|---|---|
| SupportWindow | 12 releases | A Microsoft suporta versões do agent lançadas no último ano (~releases mensais) |
| AutoUpgradeTolerance | 1 | O upgrade automático mantém o agent a até uma versão da latest |
| MinAutoUpgradeVersion | 1.57 | Upgrade automático disponível a partir do agent 1.57 |
| **SecurityFloorVersion** | **1.61** | Agents abaixo dela têm CVEs conhecidos de elevação de privilégio local (CVE-2025-49692, CVE-2025-26627, CVE-2025-55316, CVE-2026-26117) – mesmo critério do [Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) |
| LatestOverride | (vazio) | Força a versão latest quando não há sinal do Azure |

## Deploy

- Botão **Deploy to Azure** acima → escolha assinatura / resource group → abra em *Azure Monitor → Workbooks*.
- **Azure CLI**: `az deployment group create -g <resource-group> --template-uri https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/main/templates/arc-agent-support-azuredeploy.json`
- **Manual**: Workbooks → New → *Advanced Editor* (`</>`) → cole [`arc-agent-support-workbook.json`](../arc-agent-support-workbook.json) → Apply → Save.

**Permissões:** Reader nas assinaturas / management group.

## Validação

[`scripts/Test-ArcAgentSupportWorkbook.ps1`](../../scripts/Test-ArcAgentSupportWorkbook.ps1) lê o workbook e executa todas as queries, todos os valores de filtro, variações de parâmetros e o detalhamento de todas as extensões, checando mais de 20 regras de lógica (somente leitura):

```powershell
Connect-AzAccount
./scripts/Test-ArcAgentSupportWorkbook.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Mode Matrix -OutFolder ./wb-test
```

> Os relatórios de teste contêm dados do ambiente – trate como confidenciais e nunca anexe em issues.

## Relacionados

- [Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) – avaliação de segurança pontual; este workbook é a visão contínua da parte de agent/extensões.
- [Gerenciar versões do Connected Machine agent](https://learn.microsoft.com/azure/azure-arc/servers/manage-agent) · [Resolver recomendações do Advisor para servidores Arc](https://learn.microsoft.com/azure/azure-arc/servers/resolve-azure-advisor-recommendations)

Veja o [CHANGELOG](CHANGELOG.md).
