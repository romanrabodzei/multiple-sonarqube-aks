/*
.Synopsis
    Bicep template for Virtual Network with subnets.
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.Network/virtualNetworks?tabs=bicep#template-format

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
@description('The location where the resources will be deployed.')
param location string

@description('The name of the Virtual Network.')
param virtualNetworkName string

@description('The address space for the Virtual Network.')
param virtualNetworkAddressPrefix string

@description('The Names of the Virtual Network subnets.')
param virtualSubnetNames array

@description('The address prefixes for the Virtual Network subnets.')
param virtualSubnetAddressesPrefixes array

@description('The name of the Network Security Groups to associate with subnets.')
param networkSecurityGroupNames array

/// tags
param tags object = {}

/// resources
resource res_virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: toLower(virtualNetworkName)
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
  }
  resource res_appGWSubnet 'subnets' = {
    name: toLower(virtualSubnetNames[0])
    properties: {
      addressPrefix: virtualSubnetAddressesPrefixes[0]
      serviceEndpoints: [
        { service: 'Microsoft.KeyVault' }
        { service: 'Microsoft.Storage' }
      ]
      networkSecurityGroup: {
        id: resourceId('Microsoft.Network/networkSecurityGroups', toLower(networkSecurityGroupNames[0]))
      }
      privateEndpointNetworkPolicies: 'Disabled'
    }
  }
  resource res_aksSubnet 'subnets' = {
    name: toLower(virtualSubnetNames[1])
    properties: {
      addressPrefix: virtualSubnetAddressesPrefixes[1]
      serviceEndpoints: [
        { service: 'Microsoft.KeyVault' }
        { service: 'Microsoft.CognitiveServices' }
        { service: 'Microsoft.Storage' }
        { service: 'Microsoft.ContainerRegistry' }
      ]
      networkSecurityGroup: {
        id: resourceId('Microsoft.Network/networkSecurityGroups', toLower(networkSecurityGroupNames[1]))
      }
      privateEndpointNetworkPolicies: 'Disabled'
    }
  }
}

/// outputs
output virtualNetworkId string = res_virtualNetwork.id
output appGWSubnetId string = res_virtualNetwork::res_appGWSubnet.id
output aksSubnetId string = res_virtualNetwork::res_aksSubnet.id
