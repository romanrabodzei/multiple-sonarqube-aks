/*
.Synopsis
    Bicep template to assign RBAC to a Virtual Network (e.g., Network Contributor).

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

@description('The name of the Virtual Network.')
param virtualNetworkName string

@description('The principal id (objectId) of the managed identity or service principal to grant the role to.')
param userAssignedIdentityPrincipalId string

/// resources
resource res_roleDefinitions 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: roleDefinitionGuid
}

resource res_virtualNetwork 'Microsoft.Network/virtualNetworks@2022-09-01' existing = {
  name: virtualNetworkName
}

@onlyIfNotExists()
resource res_virtualNetworkRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: res_virtualNetwork
  name: guid(roleDefinitionGuid, userAssignedIdentityPrincipalId, virtualNetworkName)
  properties: {
    roleDefinitionId: res_roleDefinitions.id
    principalId: userAssignedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
