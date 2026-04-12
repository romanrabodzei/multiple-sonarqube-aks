/*
.Synopsis
    Bicep template for Private DNS Zone with A record and VNet link.
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.Network/privateDnsZones?tabs=bicep#template-format

.NOTES
    Author     : Roman Rabodzei
    Company    : CloudWolves (cloudwolves.xyz)
    Version    : 1.0.260118

           _
       .__(.)<  (MEOW)
        \___)
~~~~~~~~~~~~~~~~~~~~~~~~
*/

/// deploymentScope
targetScope = 'resourceGroup'

/// parameters
@description('The name of the Private DNS Zone.')
param privateDnsZoneName string

@description('The resource ID of the Virtual Network to link.')
param virtualNetworkId string

@description('The name of the VNet link.')
param vnetLinkName string

@description('Enable auto-registration of VMs.')
param enableAutoRegistration bool = false

@description('A record name (e.g., mcp for mcp.steward.internal).')
param aRecordName string = ''

@description('A record IP address.')
param aRecordIpAddress string = ''

/// tags
param tags object = {}

/// resources
resource res_privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: toLower(privateDnsZoneName)
  location: 'global'
  tags: tags
  properties: {}
}

// VNet Link
resource res_vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: res_privateDnsZone
  name: toLower(vnetLinkName)
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: enableAutoRegistration
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

// A Record (optional, only created if aRecordName is provided)
resource res_aRecord 'Microsoft.Network/privateDnsZones/A@2024-06-01' = if (!empty(aRecordName) && !empty(aRecordIpAddress)) {
  parent: res_privateDnsZone
  name: toLower(aRecordName)
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: aRecordIpAddress
      }
    ]
  }
}

/// outputs
output privateDnsZoneId string = res_privateDnsZone.id
output aRecordFqdn string = !empty(aRecordName) ? '${aRecordName}.${privateDnsZoneName}' : ''
