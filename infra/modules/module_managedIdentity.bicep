/*
.Synopsis
    Bicep template for User-Assigned Managed Identity.
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.ManagedIdentity/userAssignedIdentities?tabs=bicep#template-format

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

@description('The name of the User Assigned Managed Identity to create or use.')
param managedIdentityName string

/// tags
param tags object = {}

/// resources
resource res_managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: toLower(managedIdentityName)
  location: location
  tags: tags
}

/// outputs
output managedIdentityId string = res_managedIdentity.id
output managedIdentityPrincipalId string = res_managedIdentity.properties.principalId
output managedIdentityClientId string = res_managedIdentity.properties.clientId
