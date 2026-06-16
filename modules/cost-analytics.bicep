@description('Azure region for the cost analytics resources.')
param location string

@description('Globally unique name for the cost export storage account (3-24 lowercase alphanumeric characters).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Name of the blob container that receives the Cost Management exports.')
param exportContainerName string = 'cost-exports'

@description('Name of the Log Analytics workspace that ingests the cost data.')
param workspaceName string = 'log-cost-analytics'

@description('Name of the Consumption Logic App that ingests exported cost data into Log Analytics.')
param logicAppName string = 'logic-cost-ingestion'

@description('Log Analytics custom log type (table name suffix) the cost data is written to.')
param logType string = 'CostExport'

@description('Data retention in days for the Log Analytics workspace.')
param retentionInDays int = 90

// Storage account that Cost Management writes the scheduled export files to.
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource exportContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: exportContainerName
  properties: {
    publicAccess: 'None'
  }
}

// Log Analytics workspace that the cost data is ingested into.
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

// Managed API connection used by the Logic App to send data to Log Analytics.
resource logAnalyticsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azureloganalyticsdatacollector'
  location: location
  properties: {
    displayName: 'cost-analytics-workspace'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
    }
    parameterValues: {
      username: workspace.properties.customerId
      password: workspace.listKeys().primarySharedKey
    }
  }
}

// Consumption Logic App: daily, downloads the newest export CSV via managed identity and posts the parsed rows to Log Analytics.
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          type: 'Object'
          defaultValue: {}
        }
      }
      triggers: {
        Recurrence: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Day'
            interval: 1
          }
        }
      }
      actions: {
        // Flat blob listing (REST API) authenticated with the workflow's managed identity.
        // A flat listing returns blobs in the nested export subfolders the connector trigger can't watch.
        List_Blobs: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '${storageAccount.properties.primaryEndpoints.blob}${exportContainerName}?restype=container&comp=list'
            headers: {
              'x-ms-version': '2021-08-06'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: 'https://storage.azure.com/'
            }
          }
        }
        // Strip a possible UTF-8 BOM so xml()/xpath can parse the List Blobs response.
        Compose_ListClean: {
          runAfter: {
            List_Blobs: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@replace(string(body(\'List_Blobs\')), decodeUriComponent(\'%EF%BB%BF\'), \'\')'
        }
        // Count CSV blobs across all (nested) folders.
        Compose_Count: {
          runAfter: {
            Compose_ListClean: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@int(xpath(xml(outputs(\'Compose_ListClean\')), \'count(//Blob[contains(Name, ".csv")])\'))'
        }
        // Project each CSV blob to { name, ticks(lastModified) } so we can pick the newest snapshot.
        Select_Blobs: {
          runAfter: {
            Compose_Count: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@range(0, outputs(\'Compose_Count\'))'
            select: {
              name: '@xpath(xml(outputs(\'Compose_ListClean\')), concat(\'string((//Blob[contains(Name, ".csv")])[\', string(add(item(), 1)), \']/Name)\'))'
              ticks: '@ticks(xpath(xml(outputs(\'Compose_ListClean\')), concat(\'string((//Blob[contains(Name, ".csv")])[\', string(add(item(), 1)), \']/Properties/Last-Modified)\')))'
            }
          }
        }
        Select_Ticks: {
          runAfter: {
            Select_Blobs: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@body(\'Select_Blobs\')'
            select: '@item()[\'ticks\']'
          }
        }
        Compose_MaxTicks: {
          runAfter: {
            Select_Ticks: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@max(body(\'Select_Ticks\'))'
        }
        Filter_Latest: {
          runAfter: {
            Compose_MaxTicks: [
              'Succeeded'
            ]
          }
          type: 'Query'
          inputs: {
            from: '@body(\'Select_Blobs\')'
            where: '@equals(item()[\'ticks\'], outputs(\'Compose_MaxTicks\'))'
          }
        }
        Compose_LatestName: {
          runAfter: {
            Filter_Latest: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@first(body(\'Filter_Latest\'))[\'name\']'
        }
        // Download the newest export CSV using the workflow's managed identity.
        Get_Blob: {
          runAfter: {
            Compose_LatestName: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '@concat(\'${storageAccount.properties.primaryEndpoints.blob}${exportContainerName}/\', replace(outputs(\'Compose_LatestName\'), \' \', \'%20\'))'
            headers: {
              'x-ms-version': '2021-08-06'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: 'https://storage.azure.com/'
            }
          }
        }
        // Strip carriage returns and protect escaped quotes ("") so the quote-parity split below is reliable.
        Compose_Protected: {
          runAfter: {
            Get_Blob: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@replace(replace(string(body(\'Get_Blob\')), decodeUriComponent(\'%0D\'), \'\'), \'""\', \'__PIPE_QUOTE__\')'
        }
        // Split on the double-quote char: odd-indexed segments are the contents of quoted CSV fields.
        Compose_Segments: {
          runAfter: {
            Compose_Protected: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@split(outputs(\'Compose_Protected\'), \'"\')'
        }
        // Inside quoted segments (odd index), neutralise field/row delimiters so they survive the comma/newline split.
        Select_Segments: {
          runAfter: {
            Compose_Segments: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@range(0, length(outputs(\'Compose_Segments\')))'
            select: '@if(equals(mod(item(), 2), 1), replace(replace(outputs(\'Compose_Segments\')[item()], \',\', \'__PIPE_COMMA__\'), decodeUriComponent(\'%0A\'), \'__PIPE_NL__\'), outputs(\'Compose_Segments\')[item()])'
          }
        }
        // Rejoin without the delimiter quotes -> a clean CSV where only true delimiters remain.
        Compose_Cleaned: {
          runAfter: {
            Select_Segments: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@join(body(\'Select_Segments\'), \'\')'
        }
        Compose_Lines: {
          runAfter: {
            Compose_Cleaned: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@split(outputs(\'Compose_Cleaned\'), decodeUriComponent(\'%0A\'))'
        }
        Filter_Empty: {
          runAfter: {
            Compose_Lines: [
              'Succeeded'
            ]
          }
          type: 'Query'
          inputs: {
            from: '@outputs(\'Compose_Lines\')'
            where: '@not(equals(trim(item()), \'\'))'
          }
        }
        Compose_HeaderCells: {
          runAfter: {
            Filter_Empty: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@split(first(body(\'Filter_Empty\')), \',\')'
        }
        // Build a {columnName: index} lookup so columns are mapped by name, not by fixed position.
        Select_HeaderPairs: {
          runAfter: {
            Compose_HeaderCells: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@range(0, length(outputs(\'Compose_HeaderCells\')))'
            select: '@concat(\'"\', trim(replace(replace(string(outputs(\'Compose_HeaderCells\')[item()]), \'__PIPE_COMMA__\', \'\'), \'__PIPE_QUOTE__\', \'\')), \'":\', item())'
          }
        }
        Compose_Lookup: {
          runAfter: {
            Select_HeaderPairs: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@json(concat(\'{\', join(body(\'Select_HeaderPairs\'), \',\'), \'}\'))'
        }
        Compose_DataLines: {
          runAfter: {
            Compose_Lookup: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@skip(body(\'Filter_Empty\'), 1)'
        }
        // Map each data row to a JSON object keyed by column name, restoring protected characters.
        Select_Records: {
          runAfter: {
            Compose_DataLines: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@outputs(\'Compose_DataLines\')'
            select: {
              Date: '@trim(replace(replace(replace(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'Date\'], 9999)], \'\')), \'__PIPE_COMMA__\', \',\'), \'__PIPE_QUOTE__\', \'"\'), \'__PIPE_NL__\', \' \'))'
              SubscriptionId: '@trim(replace(replace(replace(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'SubscriptionId\'], 9999)], split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'SubscriptionGuid\'], 9999)], \'\')), \'__PIPE_COMMA__\', \',\'), \'__PIPE_QUOTE__\', \'"\'), \'__PIPE_NL__\', \' \'))'
              SubscriptionName: '@trim(replace(replace(replace(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'SubscriptionName\'], 9999)], \'\')), \'__PIPE_COMMA__\', \',\'), \'__PIPE_QUOTE__\', \'"\'), \'__PIPE_NL__\', \' \'))'
              ResourceGroup: '@trim(replace(replace(replace(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'ResourceGroup\'], 9999)], split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'ResourceGroupName\'], 9999)], \'\')), \'__PIPE_COMMA__\', \',\'), \'__PIPE_QUOTE__\', \'"\'), \'__PIPE_NL__\', \' \'))'
              ResourceId: '@trim(replace(replace(replace(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'ResourceId\'], 9999)], split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'InstanceId\'], 9999)], \'\')), \'__PIPE_COMMA__\', \',\'), \'__PIPE_QUOTE__\', \'"\'), \'__PIPE_NL__\', \' \'))'
              ConsumedService: '@trim(replace(replace(replace(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'ConsumedService\'], 9999)], \'\')), \'__PIPE_COMMA__\', \',\'), \'__PIPE_QUOTE__\', \'"\'), \'__PIPE_NL__\', \' \'))'
              MeterCategory: '@trim(replace(replace(replace(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'MeterCategory\'], 9999)], \'\')), \'__PIPE_COMMA__\', \',\'), \'__PIPE_QUOTE__\', \'"\'), \'__PIPE_NL__\', \' \'))'
              Currency: '@trim(replace(replace(replace(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'BillingCurrency\'], 9999)], split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'BillingCurrencyCode\'], 9999)], split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'Currency\'], 9999)], \'\')), \'__PIPE_COMMA__\', \',\'), \'__PIPE_QUOTE__\', \'"\'), \'__PIPE_NL__\', \' \'))'
              Tags: '@trim(replace(replace(replace(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'Tags\'], 9999)], \'\')), \'__PIPE_COMMA__\', \',\'), \'__PIPE_QUOTE__\', \'"\'), \'__PIPE_NL__\', \' \'))'
              Snapshot: '@outputs(\'Compose_LatestName\')'
              Cost: '@if(empty(trim(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'CostInBillingCurrency\'], 9999)], split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'Cost\'], 9999)], split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'PreTaxCost\'], 9999)], \'\')))), 0, float(trim(string(coalesce(split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'CostInBillingCurrency\'], 9999)], split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'Cost\'], 9999)], split(item(), \',\')?[coalesce(outputs(\'Compose_Lookup\')?[\'PreTaxCost\'], 9999)], \'\')))))'
            }
          }
        }
        Send_data_to_Log_Analytics: {
          runAfter: {
            Select_Records: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/api/logs'
            body: '@body(\'Select_Records\')'
            headers: {
              'Log-Type': logType
            }
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          azureloganalyticsdatacollector: {
            connectionId: logAnalyticsConnection.id
            connectionName: logAnalyticsConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
          }
        }
      }
    }
  }
}

// Storage Blob Data Reader for the Logic App identity so it can read exported blobs via managed identity.
resource blobReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, logicApp.id, '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Resource ID of the cost export storage account.')
output storageAccountId string = storageAccount.id

@description('Name of the blob container receiving the cost exports.')
output exportContainerName string = exportContainer.name

@description('Resource ID of the Log Analytics workspace.')
output workspaceId string = workspace.id

@description('Resource ID of the cost ingestion Logic App.')
output logicAppId string = logicApp.id
