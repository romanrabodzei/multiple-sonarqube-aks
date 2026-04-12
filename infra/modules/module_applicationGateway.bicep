/*
.Synopsis
    Bicep template for Application Gateway.
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.Network/applicationGateways?tabs=bicep#template-format

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

/// parameters and variables
@description('The location where the resources will be deployed.')
param location string

@description('The name of the Application Gateway.')
param applicationGatewayName string

@description('The Id of the Application Gateway Web Application Firewall Policy.')
param wafPolicyId string

@description('The Id of the user-assigned identity.')
param managedIdentityId string

@description('The Id of the public IP address.')
param publicIPAddressId string

@description('The Id of the AppGW subnet.')
param virtualNetworkSubnetId string

/// tags
@description('The tags for the resources.')
param tags object

/// resources
@onlyIfNotExists()
resource res_applicationGateway 'Microsoft.Network/applicationGateways@2024-01-01' = {
  name: toLower(applicationGatewayName)
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewaySubnetConfig'
        properties: {
          subnet: {
            id: virtualNetworkSubnetId
          }
        }
      }
    ]
    sslCertificates: []
    trustedRootCertificates: []
    trustedClientCertificates: []
    sslProfiles: []
    frontendIPConfigurations: [
      {
        name: 'appGwFrontendPublicIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddressId
          }
        }
      }
      {
        name: 'appGwFrontendPrivateIp'
        properties: {
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: virtualNetworkSubnetId
          }
          privateIPAddress: '10.5.99.10'
        }
      }
    ]
    frontendPorts: [
      {
        name: 'http'
        properties: { port: 80 }
      }
    ]
    backendAddressPools: [
      {
        name: 'agw-sq-bep-001'
        properties: {
          backendAddresses: []
        }
      }
    ]
    loadDistributionPolicies: []
    backendHttpSettingsCollection: [
      {
        name: 'agw-sq-http-001'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 30
        }
      }
    ]
    httpListeners: [
      {
        name: 'agw-sq-listener-http-001'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendIPConfigurations',
              applicationGatewayName,
              'appGwFrontendPublicIp'
            )
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'http')
          }
          protocol: 'Http'
        }
      }
    ]
    urlPathMaps: []
    requestRoutingRules: [
      {
        name: 'agw-sq-rule-http-001'
        properties: {
          ruleType: 'Basic'
          priority: 1
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              applicationGatewayName,
              'agw-sq-listener-http-001'
            )
          }
          backendAddressPool: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendAddressPools',
              applicationGatewayName,
              'agw-sq-bep-001'
            )
          }
          backendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              applicationGatewayName,
              'agw-sq-http-001'
            )
          }
        }
      }
    ]
    probes: []
    rewriteRuleSets: []
    redirectConfigurations: []
    privateLinkConfigurations: []
    sslPolicy: {
      policyType: 'Predefined'
      policyName: 'AppGwSslPolicy20220101'
    }
    enableHttp2: false
    firewallPolicy: {
      id: wafPolicyId
    }
  }
}

/// output
output applicationGatewayId string = res_applicationGateway.id
