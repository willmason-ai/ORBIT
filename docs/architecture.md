# Architecture

## High-level flow

```
Engineer (presidio.com)                      Supervisor (presidiorocks.com)
        │                                              │
        │ email + .pptx                                │ browser (Entra SSO)
        ▼                                              ▼
┌─────────────────────┐                      ┌──────────────────────────┐
│ orbit@presidiorocks │                      │ React dashboard (B1)     │
│ (O365 shared mbx)   │                      │   MSAL.js → bearer token │
└─────────┬───────────┘                      └────────────┬─────────────┘
          │ Logic App (orbit-ingestor)                    │
          │  • filter on attachment + domain              │
          │  • write .pptx + .json sidecar to blob        │
          ▼                                               │
┌─────────────────────┐                                   │
│ Blob: orbit-pptx-raw│                                   │
│ Lifecycle → Archive │                                   │
│ after 730 days      │                                   │
└─────────┬───────────┘                                   │
          │ Blob trigger                                  │
          ▼                                               │
┌─────────────────────────────────────────┐               │
│ Function App — orbit_parser             │               │
│  1. python-pptx structured extraction   │               │
│  2. Document Intelligence fallback      │               │
│  3. Claude Sonnet 4.6 agent → JSON      │               │
│  4. pyodbc writes to Azure SQL          │               │
└─────────┬───────────────────────────────┘               │
          │ on RED / low-confidence / new project         │
          ▼                                               │
┌─────────────────────┐                                   │
│ Logic App — notifier│ → supervisor inbox                │
└─────────────────────┘                                   │
                                                          │
┌─────────────────────────────────────────┐               │
│ Function App — orbit_api (FastAPI ASGI) │◀──────────────┘
│  Entra ID bearer validation             │  REST
│  Supervisor vs Engineer role gating     │
└─────────┬───────────────────────────────┘
          │ SQL (read-only views for the dashboard)
          ▼
┌─────────────────────┐
│ Azure SQL orbitdb   │  Serverless GP_S_Gen5_1, auto-pause 60 min
└─────────────────────┘
```

## Components

| Component | Type | Purpose |
|---|---|---|
| `logic-orbit-ingestor` | Logic App (Consumption) | Trigger on new mail in shared mailbox, upload PPTX + sidecar JSON to blob |
| `storbitraw` / `orbit-pptx-raw` | Storage Account + container | Durable store for raw decks; lifecycle policy tiers to Archive after 730 days |
| `func-orbit` · `orbit_parser` | Azure Function (Python, blob trigger) | PPTX → Claude → SQL pipeline |
| `func-orbit` · `orbit_api` | Azure Function (HTTP, AsgiFunctionApp) | FastAPI REST surface, Entra ID protected |
| `logic-orbit-notifier` | Logic App (Consumption) | Supervisor alerting on RED / low-confidence / new project / new engineer |
| `sql-orbit` / `orbitdb` | Azure SQL Serverless | System of record |
| `docint-orbit` | Azure AI Document Intelligence S0 | Fallback for image-only slides |
| `kv-orbit` | Key Vault | Anthropic key, SQL conn string, DocInt creds |
| `app-orbit-dashboard` | App Service B1 Linux | React dashboard hosting |
| `orbit-dashboard` | Entra ID app registration | Bearer token issuer + app roles (Supervisor / Engineer) |

## Cross-tenant identity

Two tenants, one system:

- **`presidiorocks.com`** hosts the shared mailbox, the Entra app registration, and the supervisor accounts that sign into the dashboard.
- **`presidio.com`** hosts the engineers. They never sign into anything — they send email from their normal Outlook account, and ORBIT identifies them purely from the `From:` header.

The first time `wmason@presidio.com` submits, `db._upsert_employee` creates the row:

```
{
  email: "wmason@presidio.com",
  display_name: "Will Mason",
  domain: "presidio.com",
  first_seen: <now>,
  report_count: 1,
  is_supervisor: 0
}
```

Future submissions MERGE on `email`, bump `report_count`, and refresh `last_seen` and `display_name` (last-write-wins — supervisors can override via the employee detail page).

Supervisors are seeded manually or silently added the first time they add a note (`routers/reports.py::add_note`) — that path creates a self-record with `is_supervisor = 1` if one doesn't exist.

## Data flow invariants

- **One email = one project = one PPTX.** Engineers can send up to 8 emails per cycle; the ingestor foreach-loops attachments but every report in SQL maps to exactly one PPTX blob.
- **Blob path is the source of truth for audit.** `status_reports.blob_path` is the unambiguous pointer; `blob_url` is a convenience field with no SAS attached — SAS is minted on-demand by `/api/reports/{id}/pptx`.
- **Project matching is owner-scoped.** Fuzzy match only runs against active projects owned by the same engineer (`project_matcher.py`). A second engineer naming their project "Refresh" will not collide.
- **Writes are transactional.** `db.get_connection()` is a `autocommit=False` context manager; a failure anywhere in `upsert_status_report` rolls everything back.

## Security boundaries

1. **Mailbox:** only senders in `presidio.com` are accepted (`allowedSenderDomain` parameter in the ingestor). Anything else is cancelled before blob upload.
2. **Blob:** public access disabled, managed identity only. The API mints user-delegation SAS URLs (30-min TTL) for dashboard downloads.
3. **SQL:** password auth for Phase 1; the parameters file carries the SQL admin password and the ingestion Function uses a connection string from Key Vault. Phase 2+ can move to Azure AD auth on the SQL side.
4. **API:** every endpoint except `/api/health` requires a valid bearer token; supervisor-only endpoints are gated by the `Supervisor` role claim.
5. **Key Vault:** RBAC-only; the Function App's managed identity is granted `Key Vault Secrets User`, nothing broader.
