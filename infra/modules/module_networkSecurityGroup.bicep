/*
.Synopsis
    Bicep template for Network Security Groups — AppGW and AKS subnets.
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.Network/networkSecurityGroups?tabs=bicep#template-format

.NOTES
    Author     : Roman Rabodzei
    Version    : 1.0.260328

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

@description('The name of the NSG for App Gateway subnet.')
param appGwNsgName string

@description('The name of the NSG for AKS subnet.')
param aksNsgName string

/// tags
param tags object = {}

/// resources

// NSG for App Gateway subnet
resource res_networkSecurityGroup_appGw 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: toLower(appGwNsgName)
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'azure_infrastructure_communication_inbound'
        properties: {
          description: 'https://docs.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
          sourcePortRanges: []
          destinationPortRanges: []
          sourceAddressPrefixes: []
          destinationAddressPrefixes: []
        }
      }
      {
        name: 'allow_https_inbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
          sourcePortRanges: []
          destinationPortRanges: []
          sourceAddressPrefixes: []
          destinationAddressPrefixes: []
        }
      }
      {
        name: 'allow_load_balancer'
        properties: {
          description: 'https://docs.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
          sourcePortRanges: []
          destinationPortRanges: []
          sourceAddressPrefixes: []
          destinationAddressPrefixes: []
        }
      }
    ]
  }
}

// NSG for AKS subnet
resource res_networkSecurityGroup_aks 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: toLower(aksNsgName)
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAKSDNSUDP'
        properties: {
          description: 'Allow AKS intra-cluster DNS traffic'
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAKSDNSTCP'
        properties: {
          description: 'Allow AKS DNS TCP fallback'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 101
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAKSDNSClusterIP'
        properties: {
          description: 'Allow AKS DNS traffic to ClusterIP range'
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 102
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowInboundFromVNetToAKSNodePorts'
        properties: {
          description: 'Allow inbound traffic from VNet to AKS NodePorts (Ingress)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '30000-32767'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowInboundFromVNetToIngress'
        properties: {
          description: 'Allow inbound traffic from Virtual Network'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowInboundFromAzureLoadBalancer'
        properties: {
          description: 'Allow health probes from Azure Load Balancer'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowInboundAKSAPI'
        properties: {
          description: 'Allow AKS API server communication'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '443'
            '10250'
          ]
          sourceAddressPrefix: 'AzureCloud'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 140
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowVirtualNetworkTraffic'
        properties: {
          description: 'Allow VNet traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 150
          direction: 'Inbound'
          sourcePortRanges: []
          destinationPortRanges: []
          sourceAddressPrefixes: []
          destinationAddressPrefixes: []
        }
      }
      // {
      //   name: 'DenyAllInbound'
      //   properties: {
      //     description: 'Deny all other inbound traffic'
      //     protocol: '*'
      //     sourcePortRange: '*'
      //     destinationPortRange: '*'
      //     sourceAddressPrefix: '*'
      //     destinationAddressPrefix: '*'
      //     access: 'Deny'
      //     priority: 4096
      //     direction: 'Inbound'
      //   }
      // }
      {
        name: 'AllowOutboundToKeyVault'
        properties: {
          description: 'Allow outbound to Azure Key Vault'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureKeyVault'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowOutboundToCognitiveServices'
        properties: {
          description: 'Allow outbound to Azure OpenAI / Cognitive Services'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'CognitiveServicesManagement'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowOutboundToStorage'
        properties: {
          description: 'Allow outbound to Azure Storage'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowOutboundToACR'
        properties: {
          description: 'Allow outbound to Azure Container Registry'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureContainerRegistry'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowOutboundToEntraID'
        properties: {
          description: 'Allow outbound to Entra ID for authentication'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureActiveDirectory'
          access: 'Allow'
          priority: 140
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowOutboundToAzureMonitor'
        properties: {
          description: 'Allow outbound to Azure Monitor for Container Insights'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 150
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowOutboundToAzureARMAPI'
        properties: {
          description: 'Allow outbound to Azure Resource Manager API'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureResourceManager'
          access: 'Allow'
          priority: 160
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowOutboundInternet'
        properties: {
          description: 'Allow outbound internet for AKS operations (Ubuntu updates, etc.)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 200
          direction: 'Outbound'
        }
      }
      // {
      //   name: 'DenyAllOutbound'
      //   properties: {
      //     description: 'Deny all other outbound traffic'
      //     protocol: '*'
      //     sourcePortRange: '*'
      //     destinationPortRange: '*'
      //     sourceAddressPrefix: '*'
      //     destinationAddressPrefix: '*'
      //     access: 'Deny'
      //     priority: 4096
      //     direction: 'Outbound'
      //   }
      // }
    ]
  }
}

/// outputs
output appGwNsgId string = res_networkSecurityGroup_appGw.id
output aksNsgId string = res_networkSecurityGroup_aks.id
