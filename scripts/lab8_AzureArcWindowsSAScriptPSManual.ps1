# Define initial variables
$subscriptionId = 'YourSubscriptionID' # Enter your Subscription ID
$resourceGroupName = 'YourResourceGroupName' # Enter your Resource Group for Azure Arc resources
$location = "YourLocation" # Enter your Location for Azure Arc resources

# Connect to Azure
$account = Connect-AzAccount
$context = Set-AzContext -Subscription $subscriptionId

# Retrieve a list of non-activated machines from Azure Resource Graph
$query = @"
resources
| where type =~ "microsoft.hybridcompute/machines"
| extend status = properties.status
| extend operatingSystem = properties.osSku
| extend locationDisplayName = location
| where properties.osType =~ 'windows'
| extend licenseProfile = coalesce(properties.licenseProfile, properties.licenseProfileStorage.properties)
| extend licenseStatus = tostring(licenseProfile.licenseStatus)
| extend licenseChannel = tostring(licenseProfile.licenseChannel)
| extend productSubscriptionStatus = tostring(licenseProfile.productProfile.subscriptionStatus)
| extend softwareAssurance = licenseProfile.softwareAssurance
| extend softwareAssuranceCustomer = licenseProfile.softwareAssurance.softwareAssuranceCustomer
| extend benefitsStatus = case(
    softwareAssuranceCustomer == true, "Activated",
    (licenseStatus =~ "Licensed" and licenseChannel =~ "PGS:TB") or productSubscriptionStatus =~ "Enabled", "Activated via Pay-as-you-go",
    isnull(softwareAssurance) or isnull(softwareAssuranceCustomer) or softwareAssuranceCustomer == false, "Not activated",
    "Not activated")
| where (benefitsStatus =~ 'Not activated')
| where (operatingSystem !~ ('windows 11 enterprise'))
| where (type in~ ('Microsoft.HybridCompute/machinesSoftwareAssurance','Microsoft.HybridCompute/machines'))
| where subscriptionId == "$subscriptionId"  // Filter by provided subscriptionId
| where resourceGroup =~ "$resourceGroupName"  // Filter by provided resourceGroupName
| where location =~ "$location"  // Filter by provided location
| project name, resourceGroup, subscriptionId, operatingSystem, location
"@

Write-Host "Executing query in Azure Resource Graph..."
$result = Search-AzGraph -Query $query

# Ensure results are stored as an array
$machines = @()
if ($result) {
    $machines = $result
}

# Check if any machines were returned
if ($machines.Count -eq 0) {
    Write-Host "No non-activated machines found!"
    exit
}

# Obtain authentication token for the REST API
$profile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = [Microsoft.Azure.Commands.ResourceManager.Common.rmProfileClient]::new($profile)
$token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)

$header = @{
    'Content-Type'  = 'application/json'
    'Authorization' = 'Bearer ' + $token.AccessToken
}

# Loop to process each machine
foreach ($machine in $machines) {
    $machineName = $machine.name
    $resourceGroupName = $machine.resourceGroup
    $subscriptionId = $machine.subscriptionId

    Write-Host "`n🔹 Processing machine: $machineName (RG: $resourceGroupName, Subscription: $subscriptionId)"

    # Define URI for the REST API
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HybridCompute/machines/$machineName/licenseProfiles/default?api-version=2023-10-03-preview"

    # Create JSON payload
    $data = @{
        location = $machine.location
        properties = @{
            softwareAssurance = @{
                softwareAssuranceCustomer = $true
            }
        }
    }
    
    $json = $data | ConvertTo-Json -Depth 3

    # Execute REST API call
    try {
        $response = Invoke-RestMethod -Method PUT -Uri $uri -ContentType "application/json" -Headers $header -Body $json
        Write-Host "✅ Machine $machineName processed successfully!"
        Write-Host "API Response: $($response.properties | ConvertTo-Json -Depth 3)"
    }
    catch {
        Write-Host "⚠️ Error processing machine `${machineName}`: $_"
    }
}

Write-Host "`n✅ Script completed!"
