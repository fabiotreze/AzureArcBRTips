# Required versions of Az.Accounts and Az.ResourceGraph modules are installed

# Define the required parameters
param(
    [Parameter(Mandatory=$true)]
    [string]$subscriptionId,  # Enter your Subscription ID

    [Parameter(Mandatory=$true)]
    [string]$resourceGroupName, # Enter your Resource Group for Azure Arc resources

    [Parameter(Mandatory=$true)]
    [string]$location         # Enter your Location for Azure Arc resources
)

# Authenticate to Azure using Managed Identity - RBAC required Azure Connected Machine Resource Administrator
try {
    Write-Host "Logging in to Azure..."
    Connect-AzAccount -Identity -ErrorAction Stop
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Validate the provided subscription
$subscription = Get-AzSubscription -SubscriptionId $subscriptionId -ErrorAction SilentlyContinue
if (-not $subscription) {
    Write-Host "Subscription ID $subscriptionId not found! Ensure you have access."
    exit
}

# Set the execution context to the provided Subscription ID
Write-Host "Setting execution context to Subscription ID: $subscriptionId"
Set-AzContext -SubscriptionId $subscriptionId | Out-Null

# Query Azure Resource Graph to get the list of machines
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

$query

Write-Host "Executing query in Azure Resource Graph..."
$result = Search-AzGraph -Query $query

# Ensure the results are stored as an array
$machines = @()
if ($result) {
    $machines = $result
}

# Check if any machines were returned
if ($machines.Count -eq 0) {
    Write-Host "No unactivated machines found!"
    exit
}

$machines.name

# Loop through each machine to process
foreach ($machine in $machines) {
    $machineName = $machine.name
    $resourceGroupName = $machine.resourceGroup
    $machineSubscriptionId = $machine.subscriptionId

    Write-Host "`n🔹 Processing machine: $machineName (RG: $resourceGroupName, Subscription: $machineSubscriptionId)"

    # Define URI for the REST API
    $uri = "https://management.azure.com/subscriptions/$machineSubscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HybridCompute/machines/$machineName/licenseProfiles/default?api-version=2023-10-03-preview"

    # Get the authentication token using Managed Identity
    $secureToken = (Get-AzAccessToken -ResourceUrl "https://management.azure.com" -AsSecureString).Token
    $tokenString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken))

    $header = @{
        'Content-Type'  = 'application/json'
        'Authorization' = 'Bearer ' + $tokenString
    }

    # Create the JSON payload
    $data = @{
        location = $machine.location
        properties = @{
            softwareAssurance = @{
                softwareAssuranceCustomer = $true
            }
        }
    }

    $json = $data | ConvertTo-Json -Depth 3

    $json

    # Execute the REST API call
    try {
        $response = Invoke-RestMethod -Method PUT -Uri $uri -ContentType "application/json" -Headers $header -Body $json
        Write-Host "Machine $machineName processed successfully!"
        Write-Host "API Response: $($response.properties | ConvertTo-Json -Depth 3)"
    }
    catch {
        Write-Host "Error processing machine ${machineName}: $_"
    }
}

Write-Host "`nScript completed!"
 