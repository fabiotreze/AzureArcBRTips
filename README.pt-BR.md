# AzureArcBRTips

[![Código: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](LICENSE)
[![Docs: CC BY 4.0](https://img.shields.io/badge/docs-CC%20BY%204.0-EF9421.svg)](LICENSE-DOCS)

[English](README.md) · **Português**

Uma coleção de **projetos, workbooks, scripts, templates de implantação e orientações práticas sobre Azure Arc**. O AzureArcBRTips reúne múltiplas iniciativas, cada uma com seu objetivo, pré-requisitos, instruções de uso e histórico de versões.

> Projeto pessoal e independente de Fabio Rodrigues Vieira Costa. Não é produto nem documentação oficial da Microsoft e não possui afiliação ou endosso da Microsoft. Fornecido no estado em que se encontra, sem garantia. Leia o [aviso legal](DISCLAIMER.md#aviso-legal) antes de usar.

## Catálogo de projetos

| Projeto | Finalidade | Documentação |
|---|---|---|
| Arc Agent Support Workbook | Conformidade de versões do agent, saúde do upgrade automático, Advisor, Policy e extensões | [English](workbooks/arc-agent-support/README.md) · [Português](workbooks/arc-agent-support/README.pt-BR.md) · [Changelog](workbooks/arc-agent-support/CHANGELOG.md) |

O catálogo lista os projetos disponíveis atualmente neste repositório. Novos projetos serão adicionados conforme forem publicados. Cada projeto tem versionamento independente; a versão do workbook não representa uma versão de todo o repositório.

## Primeiros passos

1. Escolha um projeto no catálogo.
2. Leia seu guia para conhecer pré-requisitos, permissões, limitações e validação.
3. Revise o código e os templates de implantação antes de executar.
4. Teste fora de produção e avalie custos do Azure e políticas da organização.

Para o workbook atual, o [guia do projeto](workbooks/arc-agent-support/README.pt-BR.md) contém o botão **Deploy to Azure**, a importação manual, as regras configuráveis e os comandos de validação. Suas consultas são somente leitura, mas implantá-lo ou salvá-lo cria ou atualiza um recurso de workbook. Não presuma que projetos futuros serão somente leitura; confira o comportamento documentado em cada projeto.

## Estrutura

| Caminho | Finalidade |
|---|---|
| [workbooks/](workbooks/) | JSONs de workbooks do Azure Monitor e guias e changelogs de cada projeto |
| [scripts/](scripts/) | Scripts de validação, automação ou outras tarefas dos projetos |
| [templates/](templates/) | Templates de implantação de recursos do Azure |
| Documentação da raiz | Apresentação do repositório, licenças, citação, aviso legal e política de segurança |

A organização é por tipo de artefato. O guia de cada projeto conecta seu workbook, scripts e templates relacionados. Os caminhos dos artefatos existentes são preservados para links e implantações.

## Adicionando projetos futuros

- Adicione uma entrada ao catálogo nos dois READMEs da raiz.
- Use nomes descritivos para os artefatos e um guia dedicado ao projeto; não sobrescreva arquivos de outro projeto.
- Documente objetivo, pré-requisitos, permissões, efeitos de leitura/escrita, custos, limitações, implantação, validação e histórico de versões.
- Vincule os artefatos relacionados no guia do projeto. Mantenha detalhes específicos e botões de implantação nele, sem transformar a raiz em guia de um único projeto.
- Crie diretórios para novos tipos de artefato somente quando houver conteúdo para publicar.

## Privacidade e uso seguro

Exportações, saídas de scripts e relatórios de teste podem conter nomes de máquinas, IDs de recursos, informações de assinaturas e detalhes operacionais. Mantenha-os confidenciais; não os anexe a issues públicas ou commits. Os diretórios padrão dos testes do workbook estão no [.gitignore](.gitignore), mas locais personalizados de saída e projetos futuros precisam de revisão própria.

Use menor privilégio e confira as recomendações na documentação oficial atual. Resultados de análise não garantem suporte, segurança ou conformidade. Consulte o [aviso legal](DISCLAIMER.md#aviso-legal).

## Feedback e segurança

Para bugs e sugestões, [abra uma issue](https://github.com/fabiotreze/AzureArcBRTips/issues) com passos de reprodução sem dados sensíveis. Informe o nome do projeto, versão ou commit, método de execução/implantação e mensagem de erro, sem credenciais ou dados do ambiente.

Para vulnerabilidades, siga a [política de segurança](SECURITY.md); não divulgue detalhes em issues públicas.

## Licença e citação

- **Código, scripts, JSONs de workbooks e templates de implantação:** [MIT](LICENSE).
- **Documentação em arquivos separados:** [CC BY 4.0](LICENSE-DOCS).
- Conteúdo de terceiros e marcas permanecem com seus respectivos titulares.

Atribuição sugerida: *AzureArcBRTips por Fabio Rodrigues Vieira Costa, https://github.com/fabiotreze/AzureArcBRTips*. Metadados para citação estão em [CITATION.cff](CITATION.cff).

## Projeto relacionado

[Arc Posture Review](https://github.com/fabiotreze/arc-posture-review) é um repositório separado para avaliações pontuais de segurança do Azure Arc.
