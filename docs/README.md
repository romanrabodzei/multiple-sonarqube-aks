# SonarQube on AKS — Architecture & Operations Guide

> **Author:** Roman Rabodzei \
> **Stack:** Azure Bicep · Azure Kubernetes Service (AKS) · Helm · ArgoCD · Azure DevOps Pipelines

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Infrastructure Components](#2-infrastructure-components)
3. [Kubernetes & Helm Deployments](#3-kubernetes--helm-deployments)
4. [GitOps with ArgoCD](#4-gitops-with-argocd)
5. [Runbook: Update SonarQube Version](#5-runbook-update-sonarqube-version)
6. [Runbook: Add a New Instance](#6-runbook-add-a-new-instance)
7. [Integrating SonarQube with Azure DevOps](#7-integrating-sonarqube-with-azure-devops)

---

## 1. Architecture Overview

```text
Internet
   │  HTTPS (*.<domain>) with wildcard TLS cert
   ▼
┌─────────────────────────────────────────────────────────┐
│  Application Gateway (WAF v2)  ←  Public IP             │
│  AGIC add-on drives AG config from Ingress resources    │
└───────────────────────┬─────────────────────────────────┘
                        │  HTTP (internal, port 9000)
                        ▼
┌─────────────────────────────────────────────────────────┐
│  AKS Cluster  (sonarqube-aks-001)                       │
│                                                         │
│  sonarqube-argocd namespace                             │
│  └─ ArgoCD  ←──── Git (Azure DevOps)                    │
│       │  watches & syncs                                │
│       ▼                                                 │
│  sonarqube-server-one namespace                         │
│  ├─ StatefulSet / Pod (sonarqube-server-one-0)          │
│  ├─ ClusterIP Service  (:9000)                          │
│  ├─ Ingress (AGIC) → sonarqube-server-one.<domain>      │
│  └─ SecretProviderClass → sonarqube-db-secret           │
│                                                         │
│  sonarqube-server-two namespace                         │
│  ├─ StatefulSet / Pod (sonarqube-server-two-0)          │
│  ├─ ClusterIP Service  (:9000)                          │
│  ├─ Ingress (AGIC) → sonarqube-server-two.<domain>      │
│  └─ SecretProviderClass → sonarqube-db-secret           │
└─────────────────────────┬───────────────────────────────┘
                          │  PostgreSQL (private endpoint)
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Azure PostgreSQL Flexible Server (sonarqube-psql-001)  │
│      VNet-integrated, private DNS only                  │
└─────────────────────────────────────────────────────────┘

CSI Secrets Store add-on pulls from:
┌──────────────────────────────────────┐
│  Azure Key Vault (sonarqube-kv-001)  │
│  sonarqube-postgres-host             │
│  sonarqube-postgres-username         │
│  sonarqube-postgres-password         │
└──────────────────────────────────────┘
```

Each SonarQube instance runs in its own namespace with its own Ingress resource. TLS is terminated at the Application Gateway using a wildcard certificate (`sonarqube-wildcard`) uploaded directly to the AG — no K8s TLS secret is needed in each namespace.

---

## 2. Infrastructure Components

All infrastructure is defined in `infra/` and deployed via the **infra-deploy** Azure DevOps pipeline. Resources live in resource group `sonarqube-rg-001` (West Europe).

### Virtual Network (`module_virtualNetwork`)

- Address space `10.5.0.0/16`
- **appgw-subnet** — Application Gateway, dedicated /27
- **aks-subnet** — AKS node pool and PostgreSQL private endpoint, dedicated /22

### Network Security Group (`module_networkSecurityGroup`)

- Applied to AKS subnet; allows intra-cluster and Application Gateway traffic.

### Application Gateway (`module_applicationGateway`)

- WAF v2 SKU with WAF policy (`module_applicationGateway_wafPolicy`)
- Managed identity used for Key Vault cert access
- Public IP (`module_publicIpAddress`) assigned with stable DNS label
- Controlled entirely by AGIC — do **not** manually edit AG routing rules; they are overwritten by the controller

### AKS Cluster (`module_kubernetesCluster`)

- System node pool: `Standard_D2s_v3`
- User node pool: `Standard_D4s_v3 × 2`
- Add-ons enabled: **AGIC**, **Azure Key Vault CSI Secrets Store**, **OMS agent → Log Analytics**
- Kubelet managed identity: used by the CSI driver to authenticate to Key Vault (no pod identity / workload identity needed)

### Key Vault (`module_keyVault`)

- Public network access enabled (required for the CSI Secrets Store add-on to fetch secrets from node VMs)
- Secrets written by Bicep at deploy time:
  - `sonarqube-postgres-host` — private FQDN of the PostgreSQL server
  - `sonarqube-postgres-username` — admin login
  - `sonarqube-postgres-password` — admin password
  - `sonarqube-license-secret` — SonarQube Developer Edition license key
  - `argocd-ssh-private-key` — RSA-4096 private key used by ArgoCD to clone this repository
  - `argocd-ssh-public-key` — corresponding public key (add to Azure DevOps SSH public keys)
- RBAC: kubelet identity has `Key Vault Secrets User` role

### PostgreSQL Flexible Server (`module_postgreSqlServer`)

- VNet-integrated (private access only); reachable via `.private.postgres.database.azure.com`
- Private endpoint in AKS subnet at a static IP so CoreDNS can resolve the hostname internally
- Private DNS zone `private.postgres.database.azure.com` linked to the VNet
- One database per SonarQube instance (`sonarqube-server-one`, `sonarqube-server-two`, etc.)
- AAD admin group configured via `module_postgreSqlServer_aadAdmin`

### Log Analytics (`module_logAnalytics`)

- Receives AKS container insights and diagnostic logs from all components

### How Components Connect

| From | To | How |
| --- | --- | --- |
| Application Gateway | AKS pods | AGIC configures AG backend pools with pod IPs directly |
| AKS pods | PostgreSQL | Private endpoint in AKS subnet; DNS resolves to `10.5.x.x` |
| AKS nodes (CSI driver) | Key Vault | HTTPS over internet (KV public access); kubelet managed identity auth |
| ArgoCD (in-cluster) | Azure DevOps Git | SSH (RSA-4096 key stored in Key Vault); no pipeline agent needed |
<!-- | infra-deploy pipeline | Azure | Service connection `SonarQube-SC`; subscription-scoped deployment | -->

---

## 3. Kubernetes & Helm Deployments

### Repository Layout

```text
k8s/
├── argocd/
│   ├── app-of-apps.yaml                # Root Application — manages all instance apps
│   ├── app-server-one.yaml             # ArgoCD Application for server-one
│   ├── app-server-two.yaml             # ArgoCD Application for server-two
│   ├── argocd-values.yaml              # ArgoCD Helm values (users, RBAC, ingress config)
│   ├── ingress.yaml                    # AGIC Ingress for ArgoCD UI
│   └── namespace.yaml
└── helm/
    ├── server-one/
    │   ├── chart-values.yaml           # Helm values for this instance
    │   ├── namespace.yaml              # K8s Namespace manifest
    │   ├── secret-provider-class.yaml  # CSI SPC — pulls secrets from KV
    │   └── ingress.yaml                # AGIC Ingress for this instance
    ├── server-two/     (same structure)
```

### Instances

| Instance | Namespace | Hostname | Edition | Database |
| --- | --- | --- | --- | --- |
| sonarqube-server-one | sonarqube-server-one | server-one-sq.<domain> | Community + Branch Plugin | sonarqube-server-one |
| sonarqube-server-two | sonarqube-server-two | server-two-sq.<domain> | Community + Branch Plugin | sonarqube-server-two |

### Secrets Flow

```text
Key Vault ──[CSI driver]──► SecretProviderClass
                                    │
                         (auto-creates K8s Secret)
                                    │
                            sonarqube-db-secret
                           ┌────────────────────┐
                           │   postgres-host    │
                           │   jdbc-username    │
                           │   jdbc-password    │
                           └────────────────────┘
                                    │
                         chart-values.yaml env vars
                      SONAR_JDBC_HOST / URL / USERNAME
```

The JDBC URL is assembled inside the pod at runtime:

```text
jdbc:postgresql://$(SONAR_JDBC_HOST):5432/<db_name>?sslmode=require
```

### Persistence

`persistence.enabled: false` — SonarQube uses `emptyDir` for `data/`, `logs/`, `temp/`.  
All persistent state (settings, projects, analyses, users) is stored in **PostgreSQL**.  
Elasticsearch indices (`data/es8/`) are rebuilt automatically from the DB on restart (~1–2 min).

### Azure DevOps Pipelines

Helm deployments are managed by **ArgoCD** (GitOps). Pipelines are used only for infrastructure and one-time ArgoCD setup.

| Pipeline | File | Trigger | What it does |
| --- | --- | --- | --- |
| infra-deploy | `.azure-pipelines/infra-deploy.yaml` | PR validation + manual | Bicep lint → what-if → deploy |
| argocd-deploy | `.azure-pipelines/argocd-deploy.yaml` | Manual (run once) | Installs ArgoCD, generates SSH key, registers ADO repo |
| helm-deploy | `.azure-pipelines/helm-deploy.yaml` | **Disabled — emergency fallback only** | Direct `helm upgrade` bypassing ArgoCD |

---

## 4. GitOps with ArgoCD

ArgoCD runs in the `sonarqube-argocd` namespace and manages all SonarQube Helm deployments. The UI is available at **[https://argocd.<domain>](https://argocd.<domain>)**.

### How It Works

```text
Git commit → Azure DevOps repo
                    │
                    │  ArgoCD polls every ~3 minutes
                    ▼
        ArgoCD watches k8s/argocd/
                    │
         ┌──────────┼──────────────┐
         ▼          ▼              ▼
    server-one   server-two  ...
    (namespace)  (namespace)
    ├─ namespace.yaml          applied from k8s/helm/<instance>/
    ├─ secret-provider-class.yaml
    ├─ ingress.yaml
    └─ sonarqube Helm chart    from SonarSource Helm repo
       (values from chart-values.yaml)
```

### App-of-Apps Pattern

A single root Application (`k8s/argocd/app-of-apps.yaml`) watches the `k8s/argocd/` directory. Every `app-server-*.yaml` file in that folder becomes an ArgoCD Application automatically — no manual registration needed when adding a new instance.

### Each Instance Application (three-source)

Each `app-server-*.yaml` uses three sources:

| Source | What it provides |
| --- | --- |
| Git path `k8s/helm/<instance>/` (excl. `chart-values.yaml`) | Namespace, SecretProviderClass, Ingress |
| SonarSource Helm repo — chart `sonarqube` @ `2026.2.1` | StatefulSet, Service, PDB, etc. |
| Git ref `values` | Helm value files (`chart-values.yaml`) |

### Sync Policy

- **`selfHeal: true`** — ArgoCD corrects any manual drift within ~3 minutes
- **`prune: false`** — Resources are never auto-deleted without a Git change; protects against accidental data loss
- **`CreateNamespace: true`** — Namespace is created automatically on first sync

### ArgoCD Users

Local users are defined in `k8s/argocd/argocd-values.yaml` under `configs.cm`.  
Passwords are set once via CLI (not stored in Git):

```bash
argocd login argocd.<domain> --username admin
argocd account update-password --account user_one --new-password '<password>'
argocd account update-password --account user_two --new-password '<password>'
```

---

## 5. Runbook: Update SonarQube Version

> With ArgoCD, a version update is just a Git commit — no pipeline run needed.

### Community instances (server-one, server-two, etc.)

> ⚠️ SonarQube requires a sequential upgrade path. If jumping more than one minor version,
> check whether an intermediate stop is needed. As of 2026: upgrading from anything below
> `mc1arke:26.1` to `26.x` requires running `26.1` first to apply the `202601000` DB migration.

1. Check for a new `mc1arke/sonarqube-with-community-branch-plugin` tag on Docker Hub:  
   `https://hub.docker.com/r/mc1arke/sonarqube-with-community-branch-plugin/tags`

2. Check the matching plugin JAR release on GitHub:  
   `https://github.com/mc1arke/sonarqube-community-branch-plugin/releases`

3. Edit **each** `k8s/helm/<instance>/chart-values.yaml`:

   ```yaml
   image:
     tag: <new-tag>             # e.g. 26.3.0.120487-community

   plugins:
     install:
       - "https://github.com/mc1arke/sonarqube-community-branch-plugin/releases/download/<new-version>/sonarqube-community-branch-plugin-<new-version>.jar"
   ```

   > The image tag and plugin JAR version must match.

4. Commit and push → ArgoCD detects the change within ~3 minutes and rolls out the update.

5. Monitor in the ArgoCD UI or via:

   ```bash
   kubectl logs -f <pod> -n sonarqube-<instance>
   ```

6. After the upgrade, check the SonarQube UI for any warnings about pending DB migrations via https://<instance>.<domain>/setup. If present, trigger them from the UI and wait for completion before making any further changes.


## 6. Runbook: Add a New Instance

Example: adding `sonarqube-server-<index>` → namespace `sonarqube-server-<index>` → hostname `sonarqube-server-<index>.<domain>`.

---

### Step 1 — Add DNS record

The DNS zone `<your_dns_zone_name>` lives in the `<your_dns_zone_resource_group>` resource group under the `<your_subscription_name>` subscription.

```bash
# Get the Application Gateway public IP
AG_IP=$(az network public-ip list \
  --resource-group sonarqube-rg-001 \
  --query "[?contains(name,'agw') || contains(name,'appgw')].ipAddress | [0]" \
  -o tsv)
echo "AG IP: $AG_IP"

# Create the A record in the Sunrise subscription
az network dns record-set a add-record \
  --subscription "your_subscription_name" \
  --resource-group <your_dns_zone_resource_group> \
  --zone-name <your_dns_zone_name> \
  --record-set-name <your_record_set_name> \
  --ipv4-address "$AG_IP" \
  --ttl 3600
```

Verify:

```bash
az network dns record-set a show \
  --subscription "your_subscription_name" \
  --resource-group <your_dns_zone_resource_group> \
  --zone-name <your_dns_zone_name> \
  --name <your_record_set_name> \
  --query "aRecords" -o table
```

---

### Step 2 — Register the application in Microsoft Entra ID

> Reference: [Setup in Microsoft Entra ID](https://docs.sonarsource.com/sonarqube-community-build/instance-administration/authentication/saml/ms-entra-id/setup-in-entra-id/)

The setup spans both the **App Registration** and the **Enterprise Application** created alongside it.

Naming convention: `ABC-SonarQube` for the app, `abcsonarqube` for the Application ID URI.

---

#### 2a. Create the App Registration

1. In **Microsoft Entra ID** → **App registrations** → **New registration**
2. Name: `ABC-SonarQube`
3. Supported account types: **Accounts in this organizational directory only**
4. Redirect URI: **Web** → `https://sonarqube-server-<index>.<domain>/oauth2/callback/saml`
5. Click **Register**

> ⚠️ Create via **App registrations**, not directly through Enterprise applications. Creating your own gallery-less Enterprise App from "Enterprise applications → New application" also works but you get the App Registration automatically.

---

#### 2b. Create App Roles

In the App Registration → **App roles** → **Create app role** (repeat for each):

| Display name | Allowed member types | Value | Description |
| --- | --- | --- | --- |
| `Administrator` | Users/Groups/Applications | `sonar-administrators` | Administrator |
| `User` | Users/Groups | `User` | User |
| `msiam_access` | Users/Groups | `msiam_access` | msiam_access |

---

#### 2c. Configure Token Claims

In the App Registration → **Token configuration** → **Add groups claim**:

- Select **Groups assigned to the application**
- Include in token types: **ID**, **Access**, **SAML**
- Click **Add**

---

#### 2d. Expose an API

In the App Registration → **Expose an API**:

1. **Application ID URI** → **Edit** → set to `abcsonarqube` → **Save**
2. **Add a scope**:
   - Scope name: `user_impersonation`
   - Who can consent: **Admins and users**
   - Admin consent display name: `Access ABC-SonarQube`
   - User consent display name: `Access ABC-SonarQube`
   - State: **Enabled** → **Add scope**

---

#### 2e. Configure SAML Single Sign-On

In the Enterprise Application (auto-created alongside the App Registration) → **Single sign-on** → **SAML**.

In **Basic SAML Configuration** → **Edit**:

| Field | Value |
| --- | --- |
| Identifier (Entity ID) | `sonarqube-server-<index>` |
| Reply URL (ACS URL) | `https://sonarqube-server-<index>.<your_domain>/oauth2/callback/saml` |

In **Attributes & Claims**: keep the default claims as-is. Verify the following are present:

| Claim | Value |
| --- | --- |
| Unique User Identifier (Name ID) | `user.userprincipalname` |
| `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name` | `user.userprincipalname` |
| `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress` | `user.mail` |
| `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname` | `user.givenname` |
| `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname` | `user.surname` |
| `http://schemas.microsoft.com/ws/2008/06/identity/claims/groups` | `user.groups [ApplicationGroup]` |

In **SAML Certificates**: download **Certificate (Base64)** — needed in Step 7.

---

#### 2f. Assign groups

In the Enterprise Application → **Users and groups** → **Add user/group**:

| Group | Role assigned |
| --- | --- |
| `SonarQube_Admin_Members` | **Administrator** |
| `SonarQube_User_Members` | **User** |

---

**2g. Note down these values** (needed in Step 7):

| Value | Where to find it |
| --- | --- |
| **Microsoft Entra Identifier** | Enterprise App → Single sign-on → Section 4 "Set up SonarQube" |
| **Login URL** | Enterprise App → Single sign-on → Section 4 "Set up SonarQube" |
| **Certificate (Base64)** | Downloaded in step 2e |

---

### Step 3 — Add PostgreSQL database

Add `"sonarqube-server-<index>"` to the `postgresDatabaseNames` array in `infra/main.bicepparam` and run the **infra-deploy** pipeline.

---

### Step 4 — Create the instance folder

Copy an existing community instance as a template:

```bash
cp -r k8s/helm/sonarqube-server-<index> k8s/helm/sonarqube-server-<new-index>
```

Edit `k8s/helm/sonarqube-server-<new-index>/chart-values.yaml`:

- `fullnameOverride: sonarqube-<new-index>`
- `SONAR_JDBC_URL`: change database name to `sonarqube-server-<new-index>`
- `sonar.core.serverBaseURL`: `https://sonarqube-server-<new-index>.<your_domain>`  ← required for SAML redirect

Edit `k8s/helm/sonarqube-server-<new-index>/namespace.yaml`:

- `name: sonarqube-<new-index>`

Edit `k8s/helm/sonarqube-server-<new-index>/secret-provider-class.yaml`:

- `namespace: sonarqube-<new-index>`

Edit `k8s/helm/sonarqube-server-<new-index>/ingress.yaml`:

- `namespace: sonarqube-server-<new-index>`
- `host: sonarqube-server-<new-index>.<your_domain>`
- `backend.service.name: sonarqube-server-<new-index>`

---

### Step 5 — Add the ArgoCD Application

Copy an existing application manifest:

```bash
cp k8s/argocd/app-sonarqube-server-<index>.yaml k8s/argocd/app-sonarqube-server-<new-index>.yaml
```

Edit `k8s/argocd/app-sonarqube-server-<new-index>.yaml`:

- `metadata.name: sonarqube-server-<new-index>`
- All three `path:` / `valueFiles:` references: change `sonarqube-server-<index>` → `sonarqube-server-<new-index>`
- `destination.namespace: sonarqube-server-<new-index>`

---

### Step 6 — Commit and push

```bash
git add k8s/helm/sonarqube-server-<new-index>/ k8s/argocd/app-sonarqube-server-<new-index>.yaml
git commit -m "feat: add sonarqube-server-<new-index> instance"
git push
```

ArgoCD app-of-apps picks up `app-sonarqube-server-<new-index>.yaml` within ~3 minutes and syncs the full instance — namespace, SecretProviderClass, Ingress, and the SonarQube Helm chart — automatically. No pipeline run needed.

---

### Step 7 — Configure SAML in SonarQube

> Reference: [Setup in SonarQube Community Build](https://docs.sonarsource.com/sonarqube-community-build/instance-administration/authentication/saml/ms-entra-id/setup-in-sq/)

Wait for the instance to be healthy (ArgoCD shows **Synced / Healthy**), then log in as `admin`.

> ⚠️ The default `admin` password is `admin`. SonarQube will prompt you to change it on first login — **save the new password in your secret manager** (e.g. Azure Key Vault / team vault) before continuing.

#### 7a — Create SonarQube groups

Go to **Administration** → **Security** → **Groups** and create the following two groups (the built-in `sonar-administrators` and `sonar-users` already exist):

| Group name | Purpose |
| --- | --- |
| `SonarQube_Admin_Members` | Maps to the Entra ID admin group; receives admin-level permissions |
| `SonarQube_User_Members` | Maps to the Entra ID user group; receives developer-level permissions |

> The names must match the Entra ID security group names exactly — JIT provisioning syncs group membership on login by matching these names.

After creating the groups, go to **Administration** → **Security** → **Global Permissions** and assign permissions as follows:

| Group | Administer System | Administer (Quality Gates / Profiles) | Execute Analysis | Create Projects | Create Applications |
| --- | :---: | :---: | :---: | :---: | :---: |
| `SonarQube_Admin_Members` | ✅ | ✅ / ✅ | ✅ | ✅ | ✅ |
| `SonarQube_User_Members` | — | ✅ / ✅ | ✅ | ✅ | — |

#### 7b — Configure SAML

1. Go to **Administration** → **Configuration** → **General Settings** → **Authentication** → **SAML**
2. Select **Create Configuration** and fill in the fields:

   | SonarQube field | Value |
   | --- | --- |
   | **Application ID** | `abcsonarqube` (must match the Identifier / Application ID URI set in Entra ID in Step 2e) |
   | **Provider ID** | Microsoft Entra Identifier from Step 2g |
   | **SAML login URL** | Login URL from Step 2g |
   | **Identity provider certificate** | Paste the Base64 certificate from Step 2g (full content including `-----BEGIN CERTIFICATE-----` lines) |
   | **SAML user login attribute** | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name` |
   | **SAML user name attribute** | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name` |
   | **SAML user email attribute** | *(leave empty — email is resolved via the name/login attribute)* |
   | **SAML group attribute** | `http://schemas.microsoft.com/ws/2008/06/identity/claims/role` |
   | **Provider Name** | `<your domain name> account` (shown as SSO button label on login page) |

   > ℹ️ The group attribute uses the **role** claim URI, not the groups claim URI. When a user logs in, Entra sends their assigned App Role (`sonar-administrators` for admins, `User` for regular users) in the role claim. SonarQube syncs this as the group name.  
   > Members of `ASG_SonarQube_Admin_Members` → assigned Administrator app role → receive `sonar-administrators` group in SonarQube → gain admin rights.

3. Under **Provisioning**, select **Just-in-Time user and group provisioning**
4. **Save** the configuration
5. Click **Test Configuration** — verifies the SAML response and shows parsed attributes; confirm `login` and group claims are populated
6. Click **Enable configuration**
7. Confirm the SonarQube login page now shows a **<your domain name> account** SSO button

---

## 7. Integrating SonarQube with Azure DevOps

This section covers how to connect a SonarQube instance to an Azure DevOps project and how to run analysis from both Classic and YAML pipelines.

**Prerequisite:** Install the [SonarQube extension](https://marketplace.visualstudio.com/items?itemName=SonarSource.sonarqube) from the Azure DevOps Marketplace into your ADO organisation (one-time, organisation-level).

---

### Service Connection

A service connection must be created per ADO project that wants to publish analyses to a SonarQube instance.

1. In Azure DevOps, go to **Project Settings** → **Service connections** → **New service connection**
2. Select **SonarQube** and click **Next**
3. Fill in the fields:

   | Field | Value |
   | --- | --- |
   | **Server URL** | `https://sonarqube-server-<index>.<domain>` (e.g. `https://sonarqube-server-one.<domain>`) |
   | **Token** | Analysis token generated in SonarQube (see below) |
   | **Service connection name** | e.g. `SonarQube_Server_One` |

4. Click **Verify and save**

#### Generate a SonarQube analysis token

1. Log in to the SonarQube instance as `admin` (or a dedicated service account)
2. Go to **My Account** → **Security** → **Generate Tokens**
3. Name: e.g. `ado-pipeline`, Type: **User Token** (or **Project Analysis Token** to scope to a single project)
4. Click **Generate** and copy the token immediately — it is not shown again
5. Paste it into the ADO service connection **Token** field

---

### Classic Pipeline

Add the following tasks in order inside your build pipeline. All three tasks are provided by the SonarQube extension.

| Order | Task | Purpose |
| --- | --- | --- |
| Before build | **PowerShell** | Extracts the branch name and exposes it as a pipeline variable |
| Before build | **Prepare Analysis Configuration** | Starts the SonarScanner and passes project settings |
| After build | **Run Code Analysis** | Sends results to SonarQube |
| After analysis | **Publish Quality Gate Result** | Waits for the Quality Gate and optionally breaks the build |

**PowerShell** task settings (add before **Prepare Analysis Configuration**):

| Field | Value |
| --- | --- |
| Display name | `Setting Branch Name` |
| Type | **Inline** |
| Script | See below |
| Use PowerShell Core | ✅ enabled |
| Working Directory | `$(system.defaultWorkingDirectory)` |

Inline script:

```powershell
$fullBranchName = "$(Build.SourceBranch)"
$branchName = "$($fullBranchName -replace 'refs/heads/', '')"
Write-Host "Branch Name:" $branchName
Write-Host "##vso[task.setvariable variable=branchName]$branchName"
```

**Prepare Analysis Configuration** settings:

| Field | Value |
| --- | --- |
| SonarQube Service Endpoint | Select the service connection created above |
| Project Key | Unique key for this project in SonarQube (e.g. `my-org_my-repo`) |
| Project Name | Human-readable name shown in the SonarQube UI |
| Additional Properties | `sonar.branch.name=$(branchName)` |

> ℹ️ For .NET solutions, set **Prepare Analysis Configuration** → **Scanner Mode** to `MSBuild`. For Maven/Gradle, choose the respective option. For everything else, use `CLI` and provide a `sonar-project.properties` file or inline properties.

---

### YAML Pipeline

Add the three SonarQube tasks to your `azure-pipelines.yml`. Place `SonarQubePrepare` **before** the build step and `SonarQubeAnalyze` / `SonarQubePublish` **after**.

#### .NET example

```yaml
steps:
  # Required for branch analysis: extract branch name for SonarQube's branch analysis features
  - task: PowerShell@2
    displayName: Setting Branch Name
    enabled: true
    inputs:
      targetType: "inline"
      script: |
         $fullBranchName = "$(Build.SourceBranch)"
         $branchName = "$($fullBranchName -replace 'refs/heads/', '')"
         Write-Host "Branch Name:" $branchName
         Write-Host "##vso[task.setvariable variable=branchName]$branchName"
      pwsh: true
      workingDirectory: "$(system.defaultWorkingDirectory)"

  - task: SonarQubePrepare@7
    inputs:
      SonarQube: 'SonarQube_Server_One'       # service connection name
      scannerMode: 'dotnet'               # or 'cli' / 'maven' / 'gradle'
      projectKey: 'my-org_my-repo'
      projectName: 'My Repo'
      extraProperties: |
         sonar.branch.name=$(branchName) # needed for branch analysis, remove for PR analysis
         # other optional extra properties like the following:
         # sonar.exclusions=**/obj/**,**/bin/**
         # sonar.scanner.metadataFilePath=$(Agent.TempDirectory)/SonarQube/$(Build.BuildNumber)/report-task.txt

  # your build steps here

  - task: SonarQubeAnalyze@7
    inputs:
      jdkversion: 'JAVA_HOME_21_X64'

  - task: SonarQubePublish@7
    inputs:
      pollingTimeoutSec: '300'
```

> ⚠️ `SonarQubePublish` polls the Quality Gate status. If the gate fails, the task itself succeeds by default — to **break the build** on a failed gate, go to the SonarQube project → **Administration** → **General Settings** → **DevOps Platform Integration** and enable **Fail the CI build when the Quality Gate fails**.
