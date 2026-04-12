/*
.Synopsis
    Bicep template for Public Ip Address. 
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.Network/publicIPAddresses?tabs=bicep#template-format

.NOTES
    Author     : Roman Rabodzei
    Version    : 1.0.260211

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

@description('The Public IP Address names.')
param publicIPAddressName string

/// tags
@description('The tags for the resources.')
param tags object = {}

/// resources
resource res_publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: toLower(publicIPAddressName)
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    ddosSettings: {
      protectionMode: 'VirtualNetworkInherited'
    }
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: toLower(publicIPAddressName)
      fqdn: toLower('${publicIPAddressName}.${location}.cloudapp.azure.com')
    }
  }
}

/// outputs
output publicIPAddressId string = res_publicIPAddress.id
