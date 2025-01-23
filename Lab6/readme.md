# Identificação de Certificados Próximos à Expiração com Azure Arc

Uma demanda importante na gestão híbrida é a identificação de certificados que estão próximos à expiração. Para atender a essa necessidade, utilizaremos o **Azure Arc, Azure Policy e Guest Configuration (Machine Configuration)**.

## 1. Assignment da Policy

Primeiramente, faremos o assignment da Policy **Audit Windows machines that contain certificates expiring within the specified number of days**. Essa política nos permitirá auditar máquinas Windows que possuem certificados próximos à expiração dentro de um número especificado de dias.

**É importante lembrar de habilitar o parâmetro que corresponde às máquinas híbridas do Azure Arc**. Isso garantirá que todas as máquinas, tanto locais quanto na nuvem, sejam monitoradas de forma eficaz.

Com essa abordagem, podemos garantir a conformidade e a segurança de nossos ambientes híbridos, evitando problemas relacionados à expiração de certificados.

Referência: [policy-reference](https://learn.microsoft.com/en-us/azure/virtual-machines/policy-reference)

## 2. Execução da Query KQL no Azure Resource Graph

Após o assignment da policy, podemos executar a query KQL no Azure Resource Graph para identificar os certificados próximos à expiração. Aqui está um exemplo de query:

```kusto
GuestConfigurationResources
| where type =~ 'microsoft.guestconfiguration/guestconfigurationassignments'
| project id, name, resources = properties.latestAssignmentReport.resources, vmid = tostring(split(properties.targetResourceId,'/')[(-1)]), status = tostring(properties.complianceStatus)
| extend resources = iff(isnull(resources), dynamic([{}]), resources)
| mvexpand resources
| extend reasons = resources.reasons
| extend reasons = iff(isnull(reasons), dynamic([{}]), reasons)
| mvexpand reasons
| where name == 'CertificateExpiration' and status == 'NonCompliant'
| summarize reasons_list = make_list(reasons.phrase) by id, vmid, name, status, resource = tostring(resources.resourceId)
| extend reasons_count = array_length(reasons_list)
| project id, vmid, name, status, reasons_count, resource
| order by name asc, status asc
```

Para mais opções de consulta, consulte a [azure-policy-guest-configuration](https://learn.microsoft.com/en-us/azure/governance/policy/samples/resource-graph-samples?tabs=azure-cli#azure-policy-guest-configuration)