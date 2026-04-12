/*
.Synopsis
    Bicep template for Application Gateway Web Application Firewall Policies. 
    Template: 
      - https://docs.microsoft.com/en-us/azure/templates/Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies?tabs=bicep#template-format

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

/// parameters and variables
@description('The location where the resources will be deployed.')
param location string

@description('The name of the Application Gateway Web Application Firewall Policy.')
param applicationGatewayWafPolicyName string

/// tags
@description('The tags for the resources.')
param tags object

/// resources
resource res_applicationGatewayWafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-11-01' = {
  name: toLower(applicationGatewayWafPolicyName)
  location: location
  tags: tags
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 2000
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Detection'
      jsChallengeCookieExpirationInMins: 30
      requestBodyInspectLimitInKB: 2000
      fileUploadEnforcement: true
      requestBodyEnforcement: true
    }
    customRules: []
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleGroupOverrides: []
        }
      ]
      exclusions: []
    }
  }
}

/// outputs
output applicationGatewayWafPolicyId string = res_applicationGatewayWafPolicy.id
