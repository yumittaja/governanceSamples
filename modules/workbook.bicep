@description('Azure region where the workbook is created.')
param location string

@description('Display name shown in the Azure portal workbook gallery.')
param workbookDisplayName string

@description('Workbook category, as shown in the portal workbook gallery.')
param category string = 'governance'

@description('Serialized workbook content (valid workbook JSON as a string).')
param serializedData string

@description('Source resource the workbook is scoped to. Use "azure monitor" for an unscoped workbook.')
param sourceId string = 'azure monitor'

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, workbookDisplayName)
  location: location
  kind: 'shared'
  properties: {
    category: category
    displayName: workbookDisplayName
    serializedData: serializedData
    sourceId: sourceId
    version: 'Notebook/1.0'
  }
}

@description('Resource ID of the deployed workbook.')
output workbookId string = workbook.id
