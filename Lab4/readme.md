# Segurança e Governança

## 1 - Requisitos do Laboratório

Criar um **Log Analytics Workspace**

---

### 2 - Coletando eventos de segurança do Windows

Coletar eventos de auditoria de logon para monitorar atividades de autenticação e acesso ao sistema, garantindo maior controle de segurança. Para isso, utilizaremos o **Azure Arc** com o **Azure Monitoring Agent**.

Vamos criar uma **Data Collection Rule** e usaremos o artigo de referência para eventos de segurança:  
[Audit logon events](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/basic-audit-logon-events#configure-this-audit-setting)

---

### Logon Events

| **Event ID** | **Descrição**                                                                                     |
|--------------|---------------------------------------------------------------------------------------------------|
| **4624**     | Um usuário fez login com sucesso em um computador. Para informações sobre o tipo de login, consulte a tabela **Logon Types** abaixo. |
| **4625**     | Falha de login. Uma tentativa de login foi feita com um nome de usuário desconhecido ou um nome de usuário conhecido com uma senha incorreta. |
| **4634**     | O processo de logoff foi concluído para um usuário.                                                |
| **4647**     | Um usuário iniciou o processo de logoff.                                                           |
| **4648**     | Um usuário fez login com sucesso em um computador usando credenciais explícitas, enquanto já estava logado como outro usuário. |
| **4779**     | Um usuário desconectou uma sessão de terminal sem fazer logoff.                                    |

---

### 3 - Configurações de Coleta

Para o **Data Source**, definiremos a opção **Custom**.

Já para o **Destination**, utilizaremos o **Log Analytics Workspace**, que será responsável por:
- Ingerir as informações listadas acima.
- Armazená-las conforme as configurações definidas.

### 4 - Query para Coleta de Eventos de Logon:

```bash
Security!*[System[(EventID=4624) or (EventID=4625) or (EventID=4634) or (EventID=4647) or (EventID=4648) or (EventID=4779)]]
```
Após é ir até o **Resources** e adicionar os computadores do **Azure Arc** que deverão receber a configuração relacionada a este **Data Collection Rule**. Com isso, deverá ser instalada a extensão do **Azure Monitoring Agent** e aplicada a configuração.

---

### 5- Workbook **Link para Workbook** [Audit Logon Events](https://raw.githubusercontent.com/fabiotreze/AzureArcDemo/refs/heads/main/Lab4/AzureArc-AuditLogonEvents.workbook)
