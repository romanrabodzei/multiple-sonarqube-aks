/*
.DESCRIPTION
  Parameter file for SonarQube AKS infrastructure deployment.
  Update values to match your environment before deploying.

.NOTES
    Author     : Roman Rabodzei
    Version    : 1.0.260410
*/

using './main.bicep'

// ── Environment ────────────────────────────────────────────────────────────────
param deploymentLocation = 'westeurope'

// ── Existing PostgreSQL Flexible Server ───────────────────────────────────────
// Admin password is supplied as a secret variable in Azure Pipelines.
// AAD admin group defaults match the domain environment; override if needed.
param postgresAdminPassword = ''
param postgresAdminLogin = 'azureadmin'
param postgresDatabaseNames = [
  'sonarqube-server-one'
  'sonarqube-server-two'
]
param postgresAadAdminGroupObjectId = '3cdbf142-2aa4-436c-85dd-dp89235fa0e43'
param postgresAadAdminGroupName = 'SonarQube_Admin_Members'

// ── AKS sizing ─────────────────────────────────────────────────────────────────
// System pool: runs kube-system + AGIC — 2 vCPU / 4 GB is sufficient
param systemNodePoolVmSize = 'Standard_D2ads_v5'

// User pool: runs SonarQube pods — SonarQube CE requires ≥2 GB RAM per instance
// 5 instances × 4 GB = 20 GB minimum → Standard_D4ads_v5 (4 vCPU / 16 GB) × 2 nodes
param userNodePoolVmSize = 'Standard_D4ads_v5'
param userNodePoolCount = 2

// ── Tags ───────────────────────────────────────────────────────────────────────
param deployedBy = 'CI/CD'
