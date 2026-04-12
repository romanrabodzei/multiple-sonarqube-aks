/*
.Synopsis
    Bicep template for Azure Database for PostgreSQL Flexible Server.
    Template:
      - https://learn.microsoft.com/en-us/azure/templates/microsoft.dbforpostgresql/flexibleservers

.NOTES
    Author     : Roman Rabodzei
    Version    : 1.0.260330

           _
       .__(.)<  (MEOW)
        \___)
~~~~~~~~~~~~~~~~~~~~~~~~
*/

/// deploymentScope
targetScope = 'resourceGroup'

/// parameters
@description('The location where the resources will be deployed.')
param location string

@description('The name of the PostgreSQL Flexible Server.')
param postgresServerName string

@description('PostgreSQL major version.')
@allowed(['14', '15', '16'])
param postgresVersion string = '16'

@description('SKU name (compute size).')
param skuName string = 'Standard_B1ms'

@description('SKU tier.')
@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param skuTier string = 'Burstable'

@description('Storage size in GB.')
@minValue(32)
@maxValue(65536)
param storageSizeGB int = 128

@description('Backup retention in days.')
@minValue(7)
@maxValue(35)
param backupRetentionDays int = 7

@description('Availability zone for the primary replica.')
@allowed(['1', '2', '3'])
param availabilityZone string = '2'

@description('PostgreSQL administrator login name.')
param administratorLogin string = 'azureadmin'

@description('PostgreSQL administrator login password.')
@secure()
param administratorLoginPassword string

@description('List of PostgreSQL database names to create on the server.')
param postgresDatabaseNames array

/// tags
@description('The tags for the resources.')
param tags object = {}

/// resources
@onlyIfNotExists()
resource res_postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2025-08-01' = {
  name: toLower(postgresServerName)
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: postgresVersion
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Enabled'
      tenantId: subscription().tenantId
    }
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Disabled'
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Disabled'
    }
    availabilityZone: availabilityZone
    maintenanceWindow: {
      customWindow: 'Disabled'
    }
  }
}

resource res_advancedThreatProtection 'Microsoft.DBforPostgreSQL/flexibleServers/advancedThreatProtectionSettings@2025-08-01' = {
  parent: res_postgresServer
  name: 'Default'
  properties: {
    state: 'Enabled'
  }
}

resource res_databases 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2025-08-01' = [
  for dbName in postgresDatabaseNames: {
    parent: res_postgresServer
    name: dbName
    properties: {
      charset: 'UTF8'
      collation: 'en_US.utf8'
    }
  }
]

/// outputs
output postgresServerId string = res_postgresServer.id
// Use private hostname — server is in VNet integration mode; public FQDN is blocked
output postgresFqdn string = '${res_postgresServer.name}.private.postgres.database.azure.com'
output postgresAdminLogin string = res_postgresServer.properties.administratorLogin
