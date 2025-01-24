## Azure Arc SQL Instance - Tag Inheritance Script

## Propósito

Este repositório contém um script PowerShell chamado **Azure Arc SQL Instance - Tag Inheritance**, criado para resolver **inconsistências na gestão de tags** em cenários de integração de **máquinas SQL com o Azure Arc**.

**Por que usar este script?**  
Por padrão, a Instância SQL do Azure Arc **não herda automaticamente as tags** da VM do Azure Arc, o que pode dificultar o gerenciamento de recursos. Este script garante que as tags da VM sejam replicadas na Instância SQL associada, promovendo consistência e organização no ambiente Azure.

O script **`lab7_AzureArcSQLTags-Inheritance.ps1`** pode ser utilizado no **runbook** e está disponível na pasta **scripts** deste repositório. Você pode acessá-lo diretamente no link:  
[lab7_AzureArcSQLTags-Inheritance.ps1](https://raw.githubusercontent.com/fabiotreze/AzureArcDemo/refs/heads/main/scripts/lab7_AzureArcSQLTags-Inheritance.ps1).  

---

### Requisitos

#### Conta de Automação
- Os módulos **Az.Account** e **Az.ResourceGraph** devem estar instalados para o funcionamento correto do script.  
- Uma **identidade gerenciada** (*managed identity*) deve ser configurada para a Conta de Automação, permitindo acesso seguro aos recursos necessários no Azure.  

#### Runbook
- É necessário configurar um **agendamento** para o **runbook**, garantindo a execução automática do script em intervalos predefinidos.  

---

### Parâmetros

O script exige os seguintes parâmetros:

- **ResourceGroupName**: Nome do grupo de recursos onde a Instância SQL do Azure Arc e a VM associada estão localizadas.  
- **SubscriptionID**: ID da assinatura do Azure onde os recursos estão registrados.  
- **tagName**: Nome da tag que será aplicada à Instância SQL do Azure Arc, com base nas tags configuradas na VM associada.  

**O que isso resolve?**  
Esses parâmetros garantem que as tags sejam sincronizadas corretamente entre os recursos do Azure Arc e suas VMs relacionadas, promovendo uma gestão de recursos mais eficiente e organizada.

---

### Nota
Certifique-se de que sua Conta de Automação e os recursos no Azure estão configurados corretamente antes de executar o script.
