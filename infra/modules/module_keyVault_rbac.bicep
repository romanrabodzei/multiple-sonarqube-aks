/*
.Synopsis
    Bicep template for RBAC assignments for key vaults. 
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.Authorization/roleAssignments?tabs=bicep#template-format

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
@description('The GUID of the role definition.')
param roleDefinitionGuid string

@description('The ID of the Key Vault.')
param keyVaultName string

@description('The ID of the managed identity.')
param userAssignedIdentityPrincipalId string

/// resources
resource res_roleDefinitions 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: roleDefinitionGuid
}

resource res_keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' existing = {
  name: keyVaultName
}

@onlyIfNotExists()
resource res_keyVaultRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: res_keyVault
  name: guid(roleDefinitionGuid, userAssignedIdentityPrincipalId, keyVaultName)
  properties: {
    roleDefinitionId: res_roleDefinitions.id
    principalId: userAssignedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
