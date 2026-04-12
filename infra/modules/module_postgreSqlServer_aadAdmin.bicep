/*
.Synopsis
    Bicep template for PostgreSQL Flexible Server Entra ID (AAD) administrator.
    Deployed as a separate step AFTER private endpoints are in place, because the
    server must be network-accessible before AAD admin operations can succeed.
    Template:
      - https://learn.microsoft.com/en-us/azure/templates/microsoft.dbforpostgresql/flexibleservers/administrators

.NOTES
    Author     : Roman Rabodzei
    Version    : 1.0.260331

           _
       .__(.)<  (MEOW)
        \___)
~~~~~~~~~~~~~~~~~~~~~~~~
*/

/// deploymentScope
targetScope = 'resourceGroup'

/// parameters
@description('The name of the existing PostgreSQL Flexible Server.')
param postgresServerName string

@description('Object ID of the Entra ID group to set as AAD admin.')
param aadAdminGroupObjectId string

@description('Display name of the Entra ID admin group.')
param aadAdminGroupName string

/// resources
resource res_postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2025-08-01' existing = {
  name: toLower(postgresServerName)
}

resource res_aadAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2025-08-01' = {
  parent: res_postgresServer
  name: aadAdminGroupObjectId
  properties: {
    principalType: 'Group'
    principalName: aadAdminGroupName
    tenantId: subscription().tenantId
  }
}
