# Security and Governance

## 1 - Laboratory Requirements

Create a **Log Analytics Workspace**

---

### 2 - Collecting Windows Security Events

Collect audit logon events to monitor authentication activities and system access, ensuring better security control. For this, we will use **Azure Arc** with the **Azure Monitoring Agent**.

We will create a **Data Collection Rule** and use the reference article for security events:  
[Audit logon events](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/basic-audit-logon-events#configure-this-audit-setting)

---

### Logon Events

| **Event ID** | **Description**                                                                                     |
|--------------|-----------------------------------------------------------------------------------------------------|
| **4624**     | A user successfully logged in to a computer. For information about the type of logon, refer to the **Logon Types** table below. |
| **4625**     | Logon failure. A login attempt was made with an unknown username or a known username with an incorrect password. |
| **4634**     | The logoff process was completed for a user.                                                        |
| **4647**     | A user initiated the logoff process.                                                                |
| **4648**     | A user successfully logged into a computer using explicit credentials while already logged in as another user. |
| **4779**     | A user disconnected a terminal session without logging off.                                        |

---

### 3 - Collection Settings

For the **Data Source**, we will define the **Custom** option.

For the **Destination**, we will use the **Log Analytics Workspace**, which will be responsible for:
- Ingesting the information listed above.
- Storing it according to the defined settings.

### 4 - Query for Collecting Logon Events:

```bash
Security!*[System[(EventID=4624) or (EventID=4625) or (EventID=4634) or (EventID=4647) or (EventID=4648) or (EventID=4779)]] 
```

---

### 5- Workbook **Link to Workbook** [Audit Logon Events](https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/refs/heads/main/workbooks/lab4_AzureArc-AuditLogonEvents.workbook)
