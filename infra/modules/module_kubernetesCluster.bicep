/*
.Synopsis
    Bicep template for Azure Kubernetes Service (AKS) cluster.
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.ContainerService/managedClusters?tabs=bicep#template-format

.NOTES
    Author     : Roman Rabodzei
    Version    : 1.0.260220

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

@description('The name of the AKS cluster.')
param azureKubernetesServiceName string

@description('The Kubernetes version.')
param kubernetesVersion string = '1.35'

@description('The SKU tier for the AKS cluster.')
@allowed(['Free', 'Standard', 'Premium'])
param skuTier string = 'Free'

@description('The resource ID of the VNet subnet for AKS pods.')
param aksSubnetId string

@description('The resource ID of the Log Analytics Workspace for Container Insights.')
param logAnalyticsWorkspaceId string

@description('The resource ID of the user-assigned managed identity.')
param managedIdentityId string

@description('The name of the infrastructure resource group.')
param nodeResourceGroup string

@description('Enable Azure Policy addon.')
param enableAzurePolicy bool = true

@description('Enable Secret Store CSI Driver.')
param enableSecretStoreCSIDriver bool = true

@description('Enable Workload Identity.')
param enableWorkloadIdentity bool = true

@description('Enable OIDC Issuer.')
param enableOidcIssuer bool = true

@description('The resource ID of the Application Gateway to be used by the Ingress Controller.')
param applicationGatewayId string

@description('System node pool VM size.')
param systemNodePoolVmSize string = 'Standard_B2s'

@description('System node pool node count.')
@minValue(1)
@maxValue(10)
param systemNodePoolCount int = 1

@description('User node pool VM size.')
param userNodePoolVmSize string = 'Standard_B2ms'

@description('User node pool node count.')
@minValue(1)
@maxValue(10)
param userNodePoolCount int = 2

/// tags
param tags object = {}

/// resources
resource res_aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-02-preview' = {
  name: toLower(azureKubernetesServiceName)
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: skuTier
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: toLower(azureKubernetesServiceName)
    nodeResourceGroup: toLower(nodeResourceGroup)

    // Entra ID Integration with Azure RBAC
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      tenantID: subscription().tenantId
    }

    // Enable OIDC Issuer for Workload Identity
    oidcIssuerProfile: {
      enabled: enableOidcIssuer
    }

    // Security Profile with Workload Identity
    securityProfile: {
      workloadIdentity: {
        enabled: enableWorkloadIdentity
      }
    }

    // Network Profile - Azure CNI with Cilium
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      serviceCidr: '10.100.0.0/16'
      dnsServiceIP: '10.100.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }

    // API Server Access Profile - Public endpoint (cost-effective)
    apiServerAccessProfile: {
      enablePrivateCluster: false
      enablePrivateClusterPublicFQDN: false
    }

    // Auto-upgrade channel
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }

    // Addons
    addonProfiles: {
      // Container Insights (Azure Monitor)
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
      // Azure Policy
      azurepolicy: {
        enabled: enableAzurePolicy
        config: {
          version: 'v2'
        }
      }
      // Secret Store CSI Driver
      azureKeyvaultSecretsProvider: {
        enabled: enableSecretStoreCSIDriver
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }

      // Application Gateway Ingress Controller
      ingressApplicationGateway: {
        enabled: true
        config: {
          applicationGatewayId: applicationGatewayId
        }
      }
    }

    // System Node Pool
    agentPoolProfiles: [
      {
        name: 'systempool'
        mode: 'System'
        vmSize: systemNodePoolVmSize
        count: systemNodePoolCount
        enableAutoScaling: false
        osType: 'Linux'
        osSKU: 'AzureLinux'
        vnetSubnetID: aksSubnetId
        maxPods: 30
        type: 'VirtualMachineScaleSets'
        availabilityZones: []
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        nodeLabels: {
          'nodepool-type': 'system'
          workload: 'system'
        }
        tags: tags
      }
    ]

    // Disable local accounts (Entra ID only)
    disableLocalAccounts: true

    // Enable Azure RBAC for Kubernetes authorization
    enableRBAC: true
  }
}

// User Node Pool (separate resource for better management)
resource res_userNodePool 'Microsoft.ContainerService/managedClusters/agentPools@2024-09-02-preview' = {
  parent: res_aksCluster
  name: 'userpool'
  properties: {
    mode: 'User'
    vmSize: userNodePoolVmSize
    count: userNodePoolCount
    enableAutoScaling: false
    osType: 'Linux'
    osSKU: 'AzureLinux'
    vnetSubnetID: aksSubnetId
    maxPods: 50
    type: 'VirtualMachineScaleSets'
    availabilityZones: []
    nodeLabels: {
      'nodepool-type': 'user'
      workload: 'application'
    }
    tags: tags
  }
}

/// outputs
output aksClusterId string = res_aksCluster.id
output azureKubernetesServiceName string = res_aksCluster.name
output aksClusterFqdn string = res_aksCluster.properties.fqdn
output aksClusterKubeletIdentityObjectId string = res_aksCluster.properties.identityProfile.kubeletidentity.objectId
output aksClusterKubeletIdentityClientId string = res_aksCluster.properties.identityProfile.kubeletidentity.clientId
output aksClusterManagedIdentityId string = res_aksCluster.properties.identityProfile.kubeletidentity.resourceId
output aksClusterAGICIdentityObjectId string = res_aksCluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
output aksClusterAGICIdentityClientId string = res_aksCluster.properties.addonProfiles.ingressApplicationGateway.identity.clientId
output aksClusterAGICIdentityId string = res_aksCluster.properties.addonProfiles.ingressApplicationGateway.identity.resourceId
output aksClusterOidcIssuerUrl string = enableOidcIssuer ? res_aksCluster.properties.oidcIssuerProfile.issuerURL : ''
output aksClusterNodeResourceGroup string = res_aksCluster.properties.nodeResourceGroup
output systemNodePoolName string = res_aksCluster.properties.agentPoolProfiles[0].name
output userNodePoolName string = res_userNodePool.name
