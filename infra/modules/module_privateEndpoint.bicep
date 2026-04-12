/*
.Synopsis
    Bicep template for Azure Private Endpoint.
    Template:
      - https://learn.microsoft.com/en-us/azure/templates/microsoft.network/privateendpoints

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
@description('The location where the resource will be deployed.')
param location string

@description('The name of the Private Endpoint.')
param privateEndpointName string

@description('Resource ID of the Private Link service to connect to.')
param privateLinkServiceId string

@description('Private Link group ID for the target resource type (e.g., postgresqlServer, vault, blob).')
param groupId string

@description('Resource ID of the subnet to place the Private Endpoint into.')
param subnetId string

@description('Optional static private IP address. When set, pins the endpoint to this IP (useful for CoreDNS host overrides).')
param staticIpAddress string = ''

/// tags
@description('The tags for the resources.')
param tags object = {}

/// variables
var useStaticIp = !empty(staticIpAddress)

/// resources
resource res_privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: toLower(privateEndpointName)
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: [groupId]
          privateLinkServiceConnectionState: {
            status: 'Approved'
            description: 'Auto-Approved'
          }
        }
      }
    ]
    manualPrivateLinkServiceConnections: []
    customNetworkInterfaceName: '${privateEndpointName}-nic'
    subnet: { id: subnetId }
    ipConfigurations: useStaticIp
      ? [
          {
            name: 'ipconfig1'
            properties: {
              groupId: groupId
              memberName: groupId
              privateIPAddress: staticIpAddress
            }
          }
        ]
      : []
  }
}

/// outputs
output privateEndpointId string = res_privateEndpoint.id
output privateEndpointNicId string = res_privateEndpoint.properties.networkInterfaces[0].id
