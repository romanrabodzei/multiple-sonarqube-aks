/*
.DESCRIPTION
  Main Bicep file to deploy SonarQube on AKS infrastructure at subscription scope.
  Creates:
    - Monitoring RG: Log Analytics Workspace
    - Infrastructure RG: VNet, AppGW, AKS, Key Vault, Storage Account, Managed Identities
  References (existing):
    - Azure PostgreSQL Flexible Server (reads FQDN + admin username; stores creds in Key Vault)

.NOTES
    Author     : Roman Rabodzei
    Version    : 1.0.260410

           _
       .__(.)<  (MEOW)
        \___)
~~~~~~~~~~~~~~~~~~~~~~~~
*/

//////////////////////////// Deployment scope ////////////////////////////

targetScope = 'subscription'

//////////////////////// Parameters and variables ////////////////////////

@description('The location for all resources.')
param deploymentLocation string = deployment().location

@description('Deployment date in the format dd-MM-yyyy.')
param deploymentDate string = utcNow('dd-MM-yyyy')

@description('PostgreSQL administrator login name.')
param postgresAdminLogin string = 'azureadmin'

@description('PostgreSQL admin password (stored securely in Key Vault by this deployment).')
@secure()
param postgresAdminPassword string = ''

@description('Names of the databases to create in PostgreSQL Flexible Server.')
param postgresDatabaseNames array

@description('Display name of the Entra ID admin group for PostgreSQL.')
param postgresAadAdminGroupName string

@description('Object ID of the Entra ID group to grant AAD admin access to PostgreSQL.')
param postgresAadAdminGroupObjectId string

@description('AKS system node pool VM size.')
param systemNodePoolVmSize string

@description('AKS user node pool VM size (SonarQube is memory-heavy).')
param userNodePoolVmSize string

@description('Number of AKS user node pool nodes.')
@minValue(1)
@maxValue(10)
param userNodePoolCount int

@description('Who triggered this deployment.')
param deployedBy string

/// Resource names
var resourceNames = {
  resourceGroupName: 'sonarqube-rg-001'
  monitoring: {
    logAnalyticsWorkspaceName: 'sonarqube-law-001'
  }
  networking: {
    virtualNetworkName: 'sonarqube-vnet-001'
    virtualNetworkAddressPrefix: '10.5.96.0/20'
    agwSubnetName: 'sonarqube-agw-snet-001'
    agwSubnetAddressPrefix: '10.5.99.0/27'
    agwNsgName: 'sonarqube-nsg-agw-001'
    aksSubnetName: 'sonarqube-aks-snet-001'
    aksSubnetAddressPrefix: '10.5.100.0/22'
    aksNsgName: 'sonarqube-nsg-aks-001'
    appGwName: 'sonarqube-agw-001'
    appGwWafPolicyName: 'sonarqube-agw-waf-policy-001'
    appGwPublicIpName: 'sonarqube-agw-pip-001'
    appGwManagedIdentityName: 'sonarqube-id-agw-001'
  }
  infrastructure: {
    aksName: 'sonarqube-aks-001'
    aksManagedIdentityName: 'sonarqube-id-aks-001'
    keyVaultName: 'sonarqube-kv-001'
    postgresServerName: 'sonarqube-psql-001'
    postgresDatabaseNames: postgresDatabaseNames
    postgresPrivateEndpointName: 'sonarqube-psql-pe-001'
    postgresPrivateEndpointAksName: 'sonarqube-psql-pe-001'
    postgresDnsZoneName: 'private.postgres.database.azure.com'
    postgresVnetLinkName: 'sonarqube-vnet-postgres-link-001'
    postgresAksPeStaticIp: '10.5.100.10'
  }
}

/// Tags applied to all resources
var tags = {
  Application: 'SonarQube'
  DeploymentDate: deploymentDate
  DeployedBy: deployedBy
}

//////////////////////////////// Resources ///////////////////////////////

/// ── Monitoring ──────────────────────────────────────────────────────

resource res_resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceNames.resourceGroupName
  location: deploymentLocation
  tags: tags
}

module mod_logAnalytics './modules/module_logAnalytics.bicep' = {
  name: 'mod_logAnalytics-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    logAnalyticsWorkspaceName: resourceNames.monitoring.logAnalyticsWorkspaceName
    tags: tags
  }
}

/// ── Network Security Groups ────────────────────────────────────────

module mod_networkSecurityGroups './modules/module_networkSecurityGroup.bicep' = {
  name: 'mod_nsgs-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    appGwNsgName: resourceNames.networking.agwNsgName
    aksNsgName: resourceNames.networking.aksNsgName
    tags: tags
  }
}

/// ── Virtual Network ─────────────────────────────────────────────────

module mod_virtualNetwork './modules/module_virtualNetwork.bicep' = {
  name: 'mod_virtualNetwork'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    virtualNetworkName: resourceNames.networking.virtualNetworkName
    virtualNetworkAddressPrefix: resourceNames.networking.virtualNetworkAddressPrefix
    virtualSubnetNames: [
      resourceNames.networking.agwSubnetName
      resourceNames.networking.aksSubnetName
    ]
    virtualSubnetAddressesPrefixes: [
      resourceNames.networking.agwSubnetAddressPrefix
      resourceNames.networking.aksSubnetAddressPrefix
    ]
    networkSecurityGroupNames: [
      resourceNames.networking.agwNsgName
      resourceNames.networking.aksNsgName
    ]
    tags: tags
  }
  dependsOn: [mod_networkSecurityGroups]
}

/// ── AppGW Managed Identity ───────────────────────────────────────────

module mod_managedIdentity_appGw './modules/module_managedIdentity.bicep' = {
  name: 'mod_managedIdentity_appGw-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    managedIdentityName: resourceNames.networking.appGwManagedIdentityName
    tags: tags
  }
}

/// ── AppGW Public IP ──────────────────────────────────────────────────

module mod_publicIp_appGw './modules/module_publicIpAddress.bicep' = {
  name: 'mod_publicIp_appGw-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    publicIPAddressName: resourceNames.networking.appGwPublicIpName
    tags: tags
  }
}

/// ── AppGW WAF Policy ───────────────────────────────────────────────

module mod_applicationGatewayWafPolicy './modules/module_applicationGateway_wafPolicy.bicep' = {
  name: 'mod_appGw_wafPolicy-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    applicationGatewayWafPolicyName: resourceNames.networking.appGwWafPolicyName
    tags: tags
  }
}

/// ── Application Gateway ──────────────────────────────────────────────

module mod_applicationGateway './modules/module_applicationGateway.bicep' = {
  name: 'mod_applicationGateway-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    applicationGatewayName: resourceNames.networking.appGwName
    wafPolicyId: mod_applicationGatewayWafPolicy.outputs.applicationGatewayWafPolicyId
    managedIdentityId: mod_managedIdentity_appGw.outputs.managedIdentityId
    publicIPAddressId: mod_publicIp_appGw.outputs.publicIPAddressId
    virtualNetworkSubnetId: mod_virtualNetwork.outputs.appGWSubnetId
    tags: tags
  }
}

/// ── AKS Managed Identity ─────────────────────────────────────────────

module mod_managedIdentity_aks './modules/module_managedIdentity.bicep' = {
  name: 'mod_managedIdentity_aks-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    managedIdentityName: resourceNames.infrastructure.aksManagedIdentityName
    tags: tags
  }
}

/// ── Key Vault ────────────────────────────────────────────────────────

module mod_keyVault './modules/module_keyVault.bicep' = {
  name: 'mod_keyVault-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    keyVaultName: resourceNames.infrastructure.keyVaultName
    tags: tags
  }
}

/// ── PostgreSQL Private DNS Zone ──────────────────────────────────────

module mod_privateDnsZone_postgres './modules/module_privateDnsZone.bicep' = {
  name: 'mod_privateDnsZone_postgres-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    privateDnsZoneName: resourceNames.infrastructure.postgresDnsZoneName
    virtualNetworkId: mod_virtualNetwork.outputs.virtualNetworkId
    vnetLinkName: resourceNames.infrastructure.postgresVnetLinkName
    tags: tags
  }
}

/// ── PostgreSQL Flexible Server ───────────────────────────────────────

module mod_postgresServer './modules/module_postgreSqlServer.bicep' = {
  name: 'mod_postgresServer-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    postgresServerName: resourceNames.infrastructure.postgresServerName
    postgresDatabaseNames: resourceNames.infrastructure.postgresDatabaseNames
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    tags: tags
  }
}


module mod_privateEndpoint_postgres './modules/module_privateEndpoint.bicep' = {
  name: 'mod_privateEndpoint_postgres-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    privateEndpointName: resourceNames.infrastructure.postgresPrivateEndpointAksName
    privateLinkServiceId: mod_postgresServer.outputs.postgresServerId
    groupId: 'postgresqlServer'
    subnetId: mod_virtualNetwork.outputs.aksSubnetId
    staticIpAddress: resourceNames.infrastructure.postgresAksPeStaticIp
    tags: tags
  }
}

/// ── Postgres credentials → Key Vault ─────────────────────────────────

/// ── PostgreSQL AAD Admin ──────────────────────────────────────────────
/// Deployed after private endpoints so the server is network-accessible.

module mod_postgresAadAdmin './modules/module_postgreSqlServer_aadAdmin.bicep' = {
  name: 'mod_postgresAadAdmin-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    postgresServerName: resourceNames.infrastructure.postgresServerName
    aadAdminGroupObjectId: postgresAadAdminGroupObjectId
    aadAdminGroupName: postgresAadAdminGroupName
  }
  dependsOn: [
    mod_privateEndpoint_postgres
    mod_privateDnsZone_postgres
  ]
}

/// ── Postgres credentials → Key Vault ─────────────────────────────────

module mod_keyVault_secret_postgresHost './modules/module_keyVault_secret.bicep' = {
  name: 'mod_kv_secret_postgresHost-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    keyVaultName: resourceNames.infrastructure.keyVaultName
    keyVaultSecretName: 'sonarqube-postgres-host'
    secretValue: mod_postgresServer.outputs.postgresFqdn
  }
  dependsOn: [mod_keyVault]
}

module mod_keyVault_secret_postgresUsername './modules/module_keyVault_secret.bicep' = {
  name: 'mod_kv_secret_postgresUsername-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    keyVaultName: resourceNames.infrastructure.keyVaultName
    keyVaultSecretName: 'sonarqube-postgres-username'
    secretValue: mod_postgresServer.outputs.postgresAdminLogin
  }
  dependsOn: [mod_keyVault]
}

/// ── AKS Cluster ──────────────────────────────────────────────────────

module mod_aksCluster './modules/module_kubernetesCluster.bicep' = {
  name: 'mod_aksCluster-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    location: deploymentLocation
    azureKubernetesServiceName: resourceNames.infrastructure.aksName
    kubernetesVersion: '1.35'
    skuTier: 'Standard'
    nodeResourceGroup: replace(resourceNames.resourceGroupName, '-rg', '-aks-rg')
    systemNodePoolVmSize: systemNodePoolVmSize
    systemNodePoolCount: 1
    userNodePoolVmSize: userNodePoolVmSize
    userNodePoolCount: userNodePoolCount
    aksSubnetId: mod_virtualNetwork.outputs.aksSubnetId
    managedIdentityId: mod_managedIdentity_aks.outputs.managedIdentityId
    applicationGatewayId: mod_applicationGateway.outputs.applicationGatewayId
    logAnalyticsWorkspaceId: mod_logAnalytics.outputs.logAnalyticsWorkspaceId
    enableAzurePolicy: true
    enableSecretStoreCSIDriver: true
    enableWorkloadIdentity: true
    enableOidcIssuer: true
    tags: tags
  }
}

/// ── RBAC ─────────────────────────────────────────────────────────────

/// AGIC identity → Contributor on AppGW
module mod_rbac_agic_appGw './modules/module_applicationGateway_rbac.bicep' = {
  name: 'mod_rbac_agic_appGw-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    roleDefinitionGuid: '4d97b98b-1d4f-4787-a291-c67834d212e7' // Network Contributor
    applicationGatewayName: resourceNames.networking.appGwName
    userAssignedIdentityPrincipalId: mod_aksCluster.outputs.aksClusterAGICIdentityObjectId
  }
}

/// AGIC identity → Network Contributor on VNet
module mod_rbac_agic_vnet './modules/module_virtualNetwork_rbac.bicep' = {
  name: 'mod_rbac_agic_vnet-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    roleDefinitionGuid: '4d97b98b-1d4f-4787-a291-c67834d212e7' // Network Contributor
    virtualNetworkName: resourceNames.networking.virtualNetworkName
    userAssignedIdentityPrincipalId: mod_aksCluster.outputs.aksClusterAGICIdentityObjectId
  }
}

/// AGIC identity → Managed Identity Operator on AppGW managed identity
module mod_rbac_agic_appGwMi './modules/module_managedIdentity_rbac.bicep' = {
  name: 'mod_rbac_agic_appGwMi-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    roleDefinitionGuid: 'f1a07417-d97a-45cb-824c-7a7467783830' // Managed Identity Operator
    managedIdentityName: resourceNames.networking.appGwManagedIdentityName
    userAssignedIdentityPrincipalId: mod_aksCluster.outputs.aksClusterAGICIdentityObjectId
  }
}

/// AKS kubelet identity → Network Contributor on VNet (required for Azure CNI)
module mod_rbac_aks_vnet './modules/module_virtualNetwork_rbac.bicep' = {
  name: 'mod_rbac_aks_vnet-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    roleDefinitionGuid: '4d97b98b-1d4f-4787-a291-c67834d212e7' // Network Contributor
    virtualNetworkName: resourceNames.networking.virtualNetworkName
    userAssignedIdentityPrincipalId: mod_aksCluster.outputs.aksClusterKubeletIdentityObjectId
  }
}

/// AKS kubelet identity → Key Vault Secrets User (for CSI Secret Store driver)
module mod_rbac_aks_keyVault './modules/module_keyVault_rbac.bicep' = {
  name: 'mod_rbac_aks_keyVault-${deploymentDate}'
  scope: res_resourceGroup
  params: {
    roleDefinitionGuid: '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
    keyVaultName: resourceNames.infrastructure.keyVaultName
    userAssignedIdentityPrincipalId: mod_aksCluster.outputs.aksClusterKubeletIdentityObjectId
  }
  dependsOn: [mod_keyVault]
}

/////////////////////////////////////// Outputs ///////////////////////////////////////

output resourceGroupName string = resourceNames.resourceGroupName
output azureKubernetesServiceName string = mod_aksCluster.outputs.azureKubernetesServiceName
output aksClusterOidcIssuerUrl string = mod_aksCluster.outputs.aksClusterOidcIssuerUrl
output aksKubeletIdentityClientId string = mod_aksCluster.outputs.aksClusterKubeletIdentityClientId
output applicationGatewayName string = resourceNames.networking.appGwName
output applicationGatewayId string = mod_applicationGateway.outputs.applicationGatewayId
output keyVaultName string = resourceNames.infrastructure.keyVaultName
output postgresFqdn string = mod_postgresServer.outputs.postgresFqdn
output postgresAksPeIp string = resourceNames.infrastructure.postgresAksPeStaticIp
