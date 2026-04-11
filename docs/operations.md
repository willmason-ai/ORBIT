# Operations Guide

## Deployment checklist (Phase 1 first-run)

1. `az group create --name rg-orbit-prod --location eastus2`
2. Fill `infra/parameters.json` — critically, `sqlAdminPassword` and `deployerObjectId`
3. `az deployment group create -g rg-orbit-prod -f infra/main.bicep -p @infra/parameters.json`
4. Load the real Anthropic key: `az keyvault secret set --vault-name kv-orbit-prod --name ANTHROPIC-API-KEY --value "sk-ant-…"`
5. Open the SQL Server firewall for your current IP, then `sqlcmd -S sql-orbit-prod.database.windows.net -d orbitdb -U orbitadmin -P '…' -i database/schema.sql -b`
6. Seed yourself as a supervisor:
   ```sql
   INSERT INTO dbo.employees (email, display_name, domain, is_supervisor)
   VALUES ('will@presidiorocks.com', 'Will Mason', 'presidiorocks.com', 1);
   ```
7. `cd functions && func azure functionapp publish func-orbit-prod --python`
8. Paste the Logic App workflows from `logic_apps/` into the designer and authorize the O365 / Blob connections
9. Build + deploy the dashboard (see [`../README.md`](../README.md))

## Monitoring

### App Insights queries

**Parser failures in the last hour**

```kusto
traces
| where operation_Name == "orbit_parser"
| where severityLevel >= 3
| project timestamp, message, operation_Name, customDimensions
| order by timestamp desc
```

**Low-confidence parses**

```kusto
customEvents
| where name == "orbit.parse.low_confidence"
| summarize count() by bin(timestamp, 1h)
```

*(Event logging is a Phase 4 addition — emit `customEvents` from `claude_agent.py` when you want this query to start returning data.)*

**API latency p95**

```kusto
requests
| where cloud_RoleName == "func-orbit-prod"
| where url !endswith "/api/health"
| summarize percentile(duration, 95) by bin(timestamp, 5m), name
| render timechart
```

### Alert rules (set up in Phase 4)

| Alert | Condition | Severity |
|---|---|---|
| Parser failures | traces with severityLevel ≥ 3 from `orbit_parser` > 0 in 15 min | High |
| RED status spike | `count(status_reports where rag_status='RED')` in 24h > 3 | Medium |
| Confidence dip | `count(status_reports where parse_confidence < 0.5)` in 24h > 2 | Medium |
| DB auto-pause churn | SQL `RESUME` events > 20/hour | Low — bump to always-on if sustained |

## Common incidents

### "A submission never showed up in the dashboard"

1. Confirm the email hit the shared mailbox (check the Office 365 trace in the admin center).
2. Logic App run history for `logic-orbit-ingestor` — look for the matching run and verify it reached `Upload_PPTX_to_Blob` successfully.
3. Check the blob container: `orbit-pptx-raw/<sender>@presidio.com/...`. If the `.pptx` exists but `.json` sidecar doesn't, the compose step downstream failed — re-run the Logic App action.
4. If both blobs exist, check App Insights for `orbit_parser` traces tagged with the blob name.
5. If the parser ran but SQL has no row, the failure is in `db.upsert_status_report` — the entire transaction rolls back, so look at the exception message.

### "Claude returned invalid JSON"

`claude_agent.py` already catches `json.JSONDecodeError` and returns a zero-confidence stub. The stub writes to SQL with `needs_review = 1` and the raw output lives in `raw_agent_json`. A supervisor can:
- Open the report in the dashboard
- Hit **Confirm extraction** to clear the flag, or
- Call `POST /api/reports/{id}/correct` with the right values

For repeated failures, pull `raw_agent_json` and re-run the prompt locally to iterate.

### "Notifier didn't fire"

The parser isn't wired to the notifier in Phase 0 — that's a Phase 2 task (see `ROADMAP.md`). Until then, notifications are manual.

### "Dashboard says 'Team Overview is empty' but I have engineers"

Two possibilities:

1. The supervisor who logged in isn't in `employees` with `is_supervisor = 1`. Seed the row and re-sign-in.
2. Engineers exist but `manager_id` isn't set. `routers/dashboard.py::team_overview` already falls back to "all active non-supervisor employees" in that case — if you're still seeing zero, it means no reporter rows have been created. Confirm at least one PPTX has been parsed end-to-end.

## Rollback

Functions and dashboard are stateless — rollback is a redeploy of the previous zip from your artifacts store (or a `git revert` + `func azure functionapp publish`).

Schema migrations (once we start writing them) should be additive-only so rollback never needs to `DROP COLUMN`. If a bad migration ships:

```bash
sqlcmd -S sql-orbit-prod.database.windows.net -d orbitdb -U orbitadmin -P '…' \
       -i database/migrations/NNNN_rollback.sql -b
```

Blobs and SQL data are authoritative — never drop the `orbit-pptx-raw` container or `TRUNCATE` a table without an explicit export first.

## Cost controls

The SQL auto-pause (60-minute idle) is the single biggest lever. If you see a cost spike, check:

1. `sql db auto-pause` telemetry — is it actually pausing?
2. App Insights sampling — default is 100% with Request events excluded; turn it down if ingestion cost is the issue.
3. Document Intelligence — only runs on slides under 20 characters of recoverable text; a spike here means decks are getting more image-heavy.
4. Claude — budget-wise, ~50 PPTX/month on Sonnet 4.6 runs $3–10. A 10× spike means the extension bundle is re-triggering on stale blobs; check the blob trigger's lease/poisoning state.
