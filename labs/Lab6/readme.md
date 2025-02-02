# Identifying Certificates Near Expiration with Azure Arc

An important task in hybrid management is identifying certificates that are near expiration. To address this need, we will use **Azure Arc, Azure Policy, and Guest Configuration (Machine Configuration)**.

## 1. Policy Assignment

First, we will assign the **Audit Windows machines that contain certificates expiring within the specified number of days** policy. This policy will allow us to audit Windows machines that have certificates close to expiration within a specified number of days.

**It’s important to remember to enable the parameter that corresponds to Azure Arc hybrid machines**. This will ensure that all machines, both on-premises and in the cloud, are effectively monitored.

With this approach, we can ensure compliance and security in our hybrid environments, preventing issues related to certificate expiration.

Reference: [policy-reference](https://learn.microsoft.com/en-us/azure/virtual-machines/policy-reference)

## 2. Running KQL Query in Azure Resource Graph

After assigning the policy, we can run the KQL query in Azure Resource Graph to identify certificates nearing expiration. Here's an example query:

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
| project id, vmid, name, status, reasons_count, reasons_list
| order by name asc, status asc
```

For more query options, refer to [azure-policy-guest-configuration](https://learn.microsoft.com/en-us/azure/governance/policy/samples/resource-graph-samples?tabs=azure-cli#azure-policy-guest-configuration)

## Keywords for Search  

`#AzureArc #Microsoft #Azure #HybridCompute #HybridCloud #Cloud #AzureMonitor #AzurePolicy #Certificate #AzureArcBRTips`