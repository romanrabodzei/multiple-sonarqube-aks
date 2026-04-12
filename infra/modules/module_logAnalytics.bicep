/*
.Synopsis
    Bicep template for Log Analytics Workspace.
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.OperationalInsights/workspaces?tabs=bicep#template-format

.NOTES
    Author     : Roman Rabodzei
    Version    : 1.0.260328

           _
       .__(.)<  (MEOW)
        \___)
~~~~~~~~~~~~~~~~~~~~~~~~
*/

/// deploymentScope
targetScope = 'resourceGroup'

/// parameters and variables
@description('The location where the resources will be deployed.')
param location string

@description('The name of the Log Analytics Workspace to create or use.')
param logAnalyticsWorkspaceName string

@description('The Log Analytics workspace SKU.')
param logAnalyticsWorkspaceSku string = 'pergb2018'

@description('The Log Analytics workspace retention in days.')
param logAnalyticsWorkspaceRetentionInDays int = 30

@description('Public network access for ingestion and query.')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

/// tags
param tags object = {}

/// resources
resource res_logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: toLower(logAnalyticsWorkspaceName)
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    retentionInDays: logAnalyticsWorkspaceRetentionInDays
    publicNetworkAccessForIngestion: publicNetworkAccess
    publicNetworkAccessForQuery: publicNetworkAccess
  }
}

/// outputs
output logAnalyticsWorkspaceId string = res_logAnalyticsWorkspace.id
