/*
.Synopsis
    Bicep template for Key Vault Secrets. 
    Template:
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.KeyVault/vaults/secrets

.NOTES
    Author     : Roman Rabodzei
    Version    : 1.0.260118

           _
       .__(.)<  (MEOW)
        \___)
~~~~~~~~~~~~~~~~~~~~~~~~
*/

/// deployment scope
targetScope = 'resourceGroup'

/// parameters and variables
@description('The name of the key vault.')
param keyVaultName string

@description('The name of the key vault secret.')
param keyVaultSecretName string
@description('The key vault secret value.')
@secure()
param secretValue string

@description('The expiry date of the key vault secret.')
#disable-next-line secure-secrets-in-params
param keyVaultSecretExpiryDate string = dateTimeAdd(utcNow(), 'P2Y')

/// resources
resource res_keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: toLower(keyVaultName)
}

@onlyIfNotExists()
resource res_keyVaultSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: res_keyVault
  name: toLower(keyVaultSecretName)
  properties: {
    attributes: {
      enabled: true
      exp: dateTimeToEpoch(keyVaultSecretExpiryDate)
    }
    value: secretValue
  }
}
