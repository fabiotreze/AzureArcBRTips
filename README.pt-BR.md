# AzureArcBRTips

[![Código: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](LICENSE)
[![Docs: CC BY 4.0](https://img.shields.io/badge/docs-CC%20BY%204.0-EF9421.svg)](LICENSE-DOCS)

[English](README.md) · **Português**

Workbook do Azure Monitor para analisar **versões do Connected Machine agent do Azure Arc, saúde do upgrade automático e extensões**. A versão atual do workbook é **4.5.0**.

> Projeto pessoal e independente de Fabio Rodrigues Vieira Costa. Não é produto nem documentação oficial da Microsoft e não possui afiliação ou endosso da Microsoft. Fornecido no estado em que se encontra, sem garantia. Leia o [aviso legal](DISCLAIMER.md#aviso-legal) antes de usar.

## O que apresenta

- Distribuição de versões do agent, conectividade e estimativa de suporte.
- Agents abaixo do piso de segurança configurável.
- Elegibilidade, progresso e falhas do upgrade automático.
- Recomendações do Azure Advisor e conformidade do Azure Policy.
- Versões de extensões, cobertura de upgrade automático e problemas agrupados por causa.

A interface e os guias detalhados estão disponíveis em inglês e português brasileiro. As referências de versão mais recente são lidas de sinais do Azure, não de uma lista de versões mantida manualmente. **O status de suporte é uma estimativa**, não uma garantia de suporte ou segurança; confira os resultados nas [release notes oficiais do agent](https://learn.microsoft.com/azure/azure-arc/servers/agent-release-notes).

## Primeiros passos

Leia o [guia do workbook](workbooks/arc-agent-support/README.pt-BR.md) para conhecer parâmetros, permissões, implantação e validação.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffabiotreze%2FAzureArcBRTips%2Fmain%2Ftemplates%2Farc-agent-support-azuredeploy.json)

- **Implantação:** o botão usa o template da branch `main` e cria um workbook do Azure Monitor no resource group selecionado. É preciso ter permissão para implantar o template e criar esse recurso; Reader sozinho não basta.
- **Importação manual:** Azure Monitor → Workbooks → New → Advanced Editor → cole o [JSON do workbook](workbooks/arc-agent-support-workbook.json) → Apply → Save.
- **Leitura dos dados:** use acesso Reader nas assinaturas ou no management group analisado. Salvar o workbook exige permissões adicionais de escrita.

As consultas do workbook e o script de validação leem dados do Azure; não atualizam agents nem corrigem recursos. Implantar ou salvar o workbook cria ou atualiza um recurso de workbook. Revise os artefatos, teste fora de produção e siga as políticas da sua organização.

## Estrutura

| Caminho | Finalidade |
|---|---|
| [JSON do workbook](workbooks/arc-agent-support-workbook.json) | Workbook para importação manual |
| [Guia em inglês](workbooks/arc-agent-support/README.md) / [guia em português](workbooks/arc-agent-support/README.pt-BR.md) | Funcionalidades, regras e uso |
| [Template ARM](templates/arc-agent-support-azuredeploy.json) | Implantação do workbook |
| [Script de validação](scripts/Test-ArcAgentSupportWorkbook.ps1) | Verificações Smoke e Matrix no Azure |
| [Changelog](workbooks/arc-agent-support/CHANGELOG.md) | Histórico de versões do workbook |

## Validação e privacidade

O script exige **PowerShell 7+**, módulos **Az.Accounts** e **Az.ResourceGraph** e um contexto autenticado no Azure. Execute a partir da raiz do repositório:

```powershell
Connect-AzAccount
./scripts/Test-ArcAgentSupportWorkbook.ps1 -WorkbookPath ./workbooks/arc-agent-support-workbook.json -Mode Smoke -OutFolder ./wb-test
```

Use `-Mode Matrix` para ampliar a cobertura de cenários. As verificações fazem requisições reais ao Azure e podem encontrar limites de chamadas das APIs.

Exportações do workbook e relatórios de teste podem conter nomes de máquinas, IDs de recursos, informações de assinaturas e detalhes operacionais. Mantenha-os confidenciais; não os anexe a issues públicas ou commits. Os diretórios padrão de saída dos testes estão no [.gitignore](.gitignore), mas isso não substitui a revisão do que será publicado.

## Feedback e segurança

Para bugs e sugestões, [abra uma issue](https://github.com/fabiotreze/AzureArcBRTips/issues) com passos de reprodução sem dados sensíveis. Informe a versão do workbook, o método de implantação e a mensagem de erro, sem credenciais ou dados do ambiente.

Para vulnerabilidades, siga a [política de segurança](SECURITY.md); não divulgue detalhes em issues públicas.

## Licença e citação

- **Código, JSON do workbook e templates ARM:** [MIT](LICENSE).
- **Documentação em arquivos separados:** [CC BY 4.0](LICENSE-DOCS).
- Conteúdo de terceiros e marcas permanecem com seus respectivos titulares.

Atribuição sugerida: *AzureArcBRTips por Fabio Rodrigues Vieira Costa, https://github.com/fabiotreze/AzureArcBRTips*. Metadados para citação estão em [CITATION.cff](CITATION.cff).

## Projeto relacionado

[Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) oferece uma avaliação pontual complementar. Este repositório concentra-se no workbook de agents e extensões.
