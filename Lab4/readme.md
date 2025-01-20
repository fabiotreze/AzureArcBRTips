# Segurança e Governança

# Requisitos do Laboratório 
1 - Criar um Log Analytics Workspace

## Coletando eventos de segurança do Windows

# Coletar eventos de auditoria de logon para monitorar atividades de autenticação e acesso ao sistema, garantindo maior controle de segurança, para isso vamos utilizar o Azure Arc com o agent do Azure Monitoring Agent.

Vamos um Data Collection Rule e vamos usar este artigo de referência para os eventos de Segurança [Audit logon events](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/basic-audit-logon-events#configure-this-audit-setting)

# Logon Events

| **Event ID** | **Description**                                                                                     |
|--------------|-----------------------------------------------------------------------------------------------------|
| **4624**     | A user successfully logged on to a computer. For information about the type of logon, see the Logon Types table below. |
| **4625**     | Logon failure. A logon attempt was made with an unknown user name or a known user name with a bad password. |
| **4634**     | The logoff process was completed for a user.                                                        |
| **4647**     | A user initiated the logoff process.                                                                |
| **4648**     | A user successfully logged on to a computer using explicit credentials while already logged on as a different user. |
| **4779**     | A user disconnected a terminal server session without logging off.                                  |

Para o nosso **Data Source**, definiremos a opção **Custom**.  

Já para o **Destination**, utilizaremos o **Log Analytics Workspace**, que será responsável por:  
- Ingerir as informações listadas abaixo.  
- Armazená-las conforme as configurações definidas. 

```bash
Security!*[System[(EventID=4624) or (EventID=4625) or (EventID=4634) or (EventID=4647) or (EventID=4648) or (EventID=4779)]]
```
Após é ir até o **Resources** e adicionar os computadores do **Azure Arc** que deverão receber a configuração relacionada a este **Data Collection Rule**. Com isso, deverá ser instalada a extensão do **Azure Monitoring Agent** e aplicada a configuração.

**Link para Workbook** [Audit Logon Events](https://raw.githubusercontent.com/fabiotreze/AzureArcDemo/refs/heads/main/Lab4/AzureArc-AuditLogonEvents.workbook)
