/*
.Synopsis
    Bicep template for Azure Key Vault.
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.KeyVault/vaults?tabs=bicep#template-format

.NOTES
    Author     : Roman Rabodzei
    Version    : 1.0.260118

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

@description('The name of the Key Vault to create or use.')
param keyVaultName string

/// tags
param tags object = {}

/// resources
resource res_keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: toLower(keyVaultName)
  tags: tags
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    // enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
      virtualNetworkRules: []
    }
  }
}

/// outputs
output keyVaultId string = res_keyVault.id
output keyVaultUri string = res_keyVault.properties.vaultUri
