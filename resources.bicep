targetScope = 'subscription'

@description('Azure region for the governance resources.')
param location string = deployment().location

@description('Name of the resource group that hosts the workbooks and cost analytics resources.')
param resourceGroupName string = 'rg-governance'

@description('Deploy the FinOps / cost management workbook and its supporting resources (storage account, Log Analytics workspace, and cost ingestion Logic App).')
param deployCostManagement bool = false

@description('Globally unique name for the cost export storage account (3-24 lowercase alphanumeric characters).')
@minLength(3)
@maxLength(24)
param costStorageAccountName string = 'stcost${uniqueString(subscription().id, resourceGroupName)}'

@description('Name of the blob container that receives the Cost Management exports.')
param costExportContainerName string = 'cost-exports'

@description('Name of the Log Analytics workspace that ingests the cost data.')
param costWorkspaceName string = 'log-cost-analytics'

@description('Name of the Consumption Logic App that ingests cost data into Log Analytics.')
param costIngestionLogicAppName string = 'logic-cost-ingestion'

// Resource group that hosts the workbooks and cost analytics resources.
// Re-declaring an existing resource group with the same name and location is idempotent.
resource governanceResourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
}

// Deploys the governance workbook.
// The workbook JSON is embedded at compile time from workbooks/governance.json.
module governanceWorkbook 'modules/workbook.bicep' = {
  scope: governanceResourceGroup
  params: {
    location: location
    workbookDisplayName: 'Azure Governance Workbook'
    category: 'governance'
    serializedData: loadTextContent('workbooks/governance.json')
  }
}

// Deploys the security workbook into the same resource group.
module securityWorkbook 'modules/workbook.bicep' = {
  scope: governanceResourceGroup
  params: {
    location: location
    workbookDisplayName: 'Azure Security Workbook'
    category: 'security'
    serializedData: loadTextContent('workbooks/security.json')
  }
}

// Deploys the FinOps / cost management workbook into the same resource group.
module finopsWorkbook 'modules/workbook.bicep' = if (deployCostManagement) {
  scope: governanceResourceGroup
  params: {
    location: location
    workbookDisplayName: 'Azure FinOps & Cost Management Workbook'
    category: 'finops'
    serializedData: loadTextContent('workbooks/finops.json')
  }
}

// Storage account, Log Analytics workspace and Logic App for cost & billing data ingestion.
module costAnalytics 'modules/cost-analytics.bicep' = if (deployCostManagement) {
  scope: governanceResourceGroup
  params: {
    location: location
    storageAccountName: costStorageAccountName
    exportContainerName: costExportContainerName
    workspaceName: costWorkspaceName
    logicAppName: costIngestionLogicAppName
  }
}

@description('Resource ID of the deployed governance workbook.')
output governanceWorkbookId string = governanceWorkbook.outputs.workbookId

@description('Resource ID of the deployed security workbook.')
output securityWorkbookId string = securityWorkbook.outputs.workbookId

@description('Resource ID of the deployed FinOps workbook. Empty when cost management is not deployed.')
output finopsWorkbookId string = deployCostManagement ? finopsWorkbook!.outputs.workbookId : ''

@description('Resource ID of the cost export storage account. Empty when cost management is not deployed.')
output costStorageAccountId string = deployCostManagement ? costAnalytics!.outputs.storageAccountId : ''

@description('Name of the cost export storage account. Use this when creating the Cost Management export manually. Empty when cost management is not deployed.')
output costStorageAccountName string = deployCostManagement ? costStorageAccountName : ''

@description('Resource ID of the cost analytics Log Analytics workspace. Empty when cost management is not deployed.')
output costWorkspaceId string = deployCostManagement ? costAnalytics!.outputs.workspaceId : ''

@description('Resource ID of the cost ingestion Logic App. Empty when cost management is not deployed.')
output costIngestionLogicAppId string = deployCostManagement ? costAnalytics!.outputs.logicAppId : ''
