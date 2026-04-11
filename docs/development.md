# Development Guide

## Prerequisites

| Tool | Version | Used for |
|---|---|---|
| Python | 3.12 | Functions |
| Node | 20 LTS | Dashboard |
| Azure Functions Core Tools | v4 | Local `func start` |
| Azure CLI + Bicep | ≥ 2.60 | Provisioning |
| `sqlcmd` | latest | Schema deploys |
| ODBC Driver 18 for SQL Server | — | pyodbc on Windows/Linux |

## Local Functions

```bash
cd functions
python -m venv .venv
. .venv/Scripts/activate       # Windows
# . .venv/bin/activate         # macOS/Linux
pip install -r requirements.txt
```

Create `functions/local.settings.json` (gitignored):

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "FUNCTIONS_EXTENSION_VERSION": "~4",
    "ANTHROPIC_API_KEY": "sk-ant-…",
    "SQL_CONNECTION_STRING": "Driver={ODBC Driver 18 for SQL Server};Server=tcp:…;Database=orbitdb;…",
    "DOCINT_ENDPOINT": "https://…cognitiveservices.azure.com/",
    "DOCINT_KEY": "…",
    "STORAGE_ACCOUNT_NAME": "storbitrawprod",
    "BLOB_CONTAINER_NAME": "orbit-pptx-raw",
    "PARSE_CONFIDENCE_THRESHOLD": "0.70",
    "PROJECT_MATCH_THRESHOLD": "0.85",
    "ORBIT_TENANT_ID": "…",
    "ORBIT_API_AUDIENCE": "api://orbit-dashboard"
  }
}
```

Run:

```bash
func start
```

The parser blob trigger binds to your dev storage; the API is available at `http://localhost:7071/api/health`.

### Exercising the parser locally

Easiest path is to drop a PPTX into `orbit-pptx-raw/<sender>@presidio.com/<timestamp>__deck.pptx` on your Azurite-backed dev storage and let the trigger fire. No sidecar needed — the parser falls back to parsing the blob name.

## Local dashboard

```bash
cd dashboard
npm install
cp .env.example .env.local   # if you add one; otherwise write it by hand
npm run dev                  # http://localhost:5173
```

`.env.local`:

```
VITE_API_BASE_URL=http://localhost:7071
VITE_TENANT_ID=<your-tenant-guid>
VITE_CLIENT_ID=<orbit-dashboard-client-id>
VITE_API_SCOPE=api://orbit-dashboard/access_as_user
```

Notes:
- MSAL insists on HTTPS for production redirect URIs but is fine with `http://localhost:5173` in dev.
- If you see CORS errors, it means the Function App isn't allowing the Vite origin — adjust `CORSMiddleware` in `functions/orbit_api/__init__.py` or add `http://localhost:5173` to the Function App's platform-level CORS list.

## Coding conventions

- **Python:** type hints everywhere, `from __future__ import annotations` at the top of every module, no `# noqa` without a reason, no bare `except`.
- **TypeScript:** `strict: true` is enabled — keep it. Prefer `type` imports (`import type { … }`) for type-only imports so Vite tree-shakes cleanly.
- **SQL:** all writes go through `pyodbc` with parameter placeholders — no f-string injection. `pyodbc.Row` objects are positional-indexed; use `row[0]` rather than `row.id` so the code doesn't depend on the driver's attribute-access mode.
- **Logging:** `logging.getLogger(__name__)` at module scope; use `log.exception(...)` inside `except:` blocks so the stack hits App Insights.
- **Commits:** small, imperative titles ("Add RAG trend chart", not "Added…"). A body is optional — prefer it when the *why* isn't obvious from the diff.

## Tests

Not scaffolded yet — Phase 4 candidate. When you add them:

- `pytest` under `functions/tests/` — unit test `pptx_extractor` and `project_matcher` with fixture decks/rows; integration test against Azurite + SQL Edge for the blob → SQL flow.
- `vitest` under `dashboard/` — component tests for `RAGBadge`, `HoursGauge`, and `MilestoneList`; Playwright for the MSAL-happy-path smoke test.

## Debugging Claude parses

Every successful parse writes the raw model output to `status_reports.raw_agent_json`. When something looks wrong on the dashboard, grab that blob:

```sql
SELECT id, parse_confidence, raw_agent_json
FROM dbo.status_reports
WHERE needs_review = 1
ORDER BY submission_at DESC;
```

Paste the JSON into a scratch file, re-run `claude_agent.extract_project_status` locally with the same PPTX bytes, and iterate on the system prompt.
