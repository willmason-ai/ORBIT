# ORBIT — Operations Reporting & Brief Intelligence Tracker

**Presidio Network Solutions — Internal**

> "Just send ORBIT the email."

Engineers email a shared mailbox with a PPTX attached. Claude extracts project name, hours, RAG status, milestones, and blockers, routes them into SQL, and supervisors see the full team picture in a dashboard. No project codes. No web forms. No special formatting.

See [`ORBIT_CLAUDE_CODE_SPEC.md`](./ORBIT_CLAUDE_CODE_SPEC.md) for the full design spec.

---

## Repo layout

```
orbit/
├── infra/                 Bicep IaC (main.bicep + parameters.json)
├── database/              Azure SQL DDL (schema.sql)
├── functions/             Single Azure Function App (Python 3.12, Flex Consumption)
│   ├── orbit_parser/      Blob-triggered PPTX → Claude → SQL pipeline
│   └── orbit_api/         FastAPI served via AsgiFunctionApp (Entra ID protected)
├── logic_apps/            Workflow JSON for ingestor + notifier
├── dashboard/             React 18 + Vite + Tailwind v4 + MSAL supervisor UI
└── README.md              This file
```

---

## Prerequisites

- Azure subscription with Owner or Contributor + User Access Administrator
- Azure CLI (`az`) ≥ 2.60 and Bicep CLI
- `sqlcmd` (or Azure Data Studio) for schema deploy
- Node 20 + npm for dashboard builds
- Python 3.12 for local Function runs (optional)
- O365 shared mailbox provisioned: `orbit@presidiorocks.com`
- Anthropic API key (Sonnet 4.6 access)

---

## Deployment

### 1. Provision Azure resources

```bash
az login
az account set --subscription <your-sub-id>
az group create --name rg-orbit-prod --location eastus2

# Edit infra/parameters.json first: sqlAdminPassword, deployerObjectId
az deployment group create \
  --resource-group rg-orbit-prod \
  --template-file infra/main.bicep \
  --parameters @infra/parameters.json
```

Capture outputs (`functionAppName`, `dashboardHost`, `sqlServerFqdn`, etc).

### 2. Load secrets into Key Vault

```bash
az keyvault secret set --vault-name kv-orbit-prod \
  --name ANTHROPIC-API-KEY --value "sk-ant-…"
# SQL / DocInt secrets are seeded by Bicep from your params.
```

### 3. Deploy schema

```bash
sqlcmd -S sql-orbit-prod.database.windows.net -d orbitdb \
       -U orbitadmin -P "<password>" -i database/schema.sql -b
```

### 4. Seed supervisors

```sql
INSERT INTO dbo.employees (email, display_name, domain, is_supervisor)
VALUES ('will@presidiorocks.com','Will Mason','presidiorocks.com',1);
```

### 5. Deploy the Function App

```bash
cd functions
func azure functionapp publish func-orbit-prod --python
```

### 6. Wire the Logic Apps

1. Open each Logic App in the Azure portal designer.
2. Paste the JSON from `logic_apps/ingestor.workflow.json` / `notifier.workflow.json`.
3. Authorize the O365 and Azure Blob API connections (interactive sign-in required).
4. Set `allowedSenderDomain = presidio.com` on the ingestor parameters.
5. Save + enable.

### 7. Entra ID app registration (manual)

Bicep can't provision app registrations, so do this once in the portal:

1. **Azure AD → App registrations → New**
   - Name: `orbit-dashboard`
   - Redirect URI (SPA): `https://app-orbit-dashboard-prod.azurewebsites.net`
2. **Expose an API**
   - Application ID URI: `api://orbit-dashboard`
   - Scope: `access_as_user`
3. **App roles**
   - `Supervisor` (Users/Groups) — full team visibility
   - `Engineer`   (Users/Groups) — own submissions (Phase 2)
4. **Assign app roles** to supervisor users under Enterprise Applications → orbit-dashboard → Users and groups.
5. Copy the application (client) ID and tenant ID for the dashboard build.

### 8. Build and deploy the dashboard

```bash
cd dashboard
npm install
cat > .env.production <<EOF
VITE_API_BASE_URL=https://func-orbit-prod.azurewebsites.net
VITE_TENANT_ID=<your-tenant-id>
VITE_CLIENT_ID=<orbit-dashboard-client-id>
VITE_API_SCOPE=api://orbit-dashboard/access_as_user
EOF
npm run build

# Deploy dist/ to App Service (zip deploy works fine)
zip -r dist.zip dist
az webapp deploy --resource-group rg-orbit-prod \
  --name app-orbit-dashboard-prod \
  --src-path dist.zip --type zip
```

---

## Engineer onboarding

Share this with engineers — that's it:

> **To update project status:** email `orbit@presidiorocks.com` with your PowerPoint status deck attached. One email = one project. No subject line format required. You can send up to 8 emails per reporting cycle if you're on 8 projects.

First time sending counts automatically; no enrollment needed.

---

## Local development

### Functions

```bash
cd functions
python -m venv .venv && . .venv/bin/activate  # or .venv\Scripts\activate on Windows
pip install -r requirements.txt

# Create local.settings.json with your dev values
func start
```

### Dashboard

```bash
cd dashboard
npm install
npm run dev    # http://localhost:5173
```

---

## Observability

- **App Insights**: traces for parser runs, API requests, and MSAL token failures.
- **Log Analytics**: long-term retention for the above.
- **Storage Account metrics**: watch `orbit-pptx-raw` ingress volume.
- Lifecycle policy tiers blobs to **Azure Archive after 730 days** automatically.

---

## Cost (steady-state, production)

~**$39–$67/month**. See spec Section 14 for the breakdown.
