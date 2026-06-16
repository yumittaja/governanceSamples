using './resources.bicep'

param resourceGroupName = 'rg-governance'

// Set to true to also deploy the FinOps workbook and its supporting cost analytics
// resources (storage account, Log Analytics workspace, and cost ingestion Logic App).
param deployCostManagement = false

// Cost & billing analytics. The storage account name defaults to a generated unique value;
// override it here if you need a specific name (3-24 lowercase alphanumeric characters).
param costExportContainerName = 'cost-exports'
param costWorkspaceName = 'log-cost-analytics'
param costIngestionLogicAppName = 'logic-cost-ingestion'
