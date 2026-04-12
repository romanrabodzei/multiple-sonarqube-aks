/*
.Synopsis
    Bicep template to assign RBAC to an Application Gateway (e.g., Network Contributor).

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

@description('The name of the Application Gateway.')
param applicationGatewayName string

@description('The principal id (objectId) of the managed identity or service principal to grant the role to.')
param userAssignedIdentityPrincipalId string

/// resources
resource res_roleDefinitions 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: roleDefinitionGuid
}

resource res_applicationGateway 'Microsoft.Network/applicationGateways@2024-01-01' existing = {
  name: applicationGatewayName
}

@onlyIfNotExists()
resource res_applicationGatewayRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: res_applicationGateway
  name: guid(roleDefinitionGuid, userAssignedIdentityPrincipalId, applicationGatewayName)
  properties: {
    roleDefinitionId: res_roleDefinitions.id
    principalId: userAssignedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
