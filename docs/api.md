# API Reference

Base URL in production: `https://func-orbit-prod.azurewebsites.net`
Auth: every endpoint except `/api/health` requires an Entra ID bearer token for `api://orbit-dashboard/access_as_user`. Supervisor-only endpoints additionally require the `Supervisor` app role claim.

Error shape: FastAPI default — `{ "detail": "string" }` with the appropriate HTTP status.

---

## Meta

### `GET /api/health`

Anonymous liveness check.

```json
{ "status": "ok" }
```

---

## Projects

### `GET /api/projects`

Query params (all optional): `search`, `rag` (`RED|AMBER|GREEN`), `employee_id`, `needs_review` (`true|false`).

Returns an array of `vw_projects_latest` rows ordered by most recent update.

```json
[
  {
    "project_id": 42,
    "project_name": "AVS Refresh — FY26",
    "customer_name": "Acme Corp",
    "owner_id": 7,
    "owner_name": "Will Mason",
    "owner_email": "wmason@presidio.com",
    "rag_status": "AMBER",
    "pct_hours_consumed": 68.5,
    "total_hours_budget": 240.0,
    "hours_consumed": 164.5,
    "last_updated": "2026-04-10T17:22:00",
    "needs_review": false,
    "latest_report_id": 118
  }
]
```

### `GET /api/projects/{id}`

Single latest-view row. 404 if project doesn't exist.

### `GET /api/projects/{id}/history`

Chronological list of every report for the project (DESC). Used by the RAG trend chart.

```json
[
  {
    "id": 118,
    "submission_at": "2026-04-10T17:22:00",
    "rag_status": "AMBER",
    "pct_hours_consumed": 68.5,
    "total_hours_budget": 240.0,
    "hours_consumed": 164.5,
    "parse_confidence": 0.91,
    "needs_review": false
  }
]
```

---

## Employees

**All endpoints under `/api/employees` require the `Supervisor` role.**

### `GET /api/employees`

All active employees, ordered by `full_name`.

### `GET /api/employees/{id}`

Detail including `first_seen`, `last_seen`, `report_count`, and supervisor notes.

### `GET /api/employees/{id}/projects`

Per-engineer list of `vw_projects_latest` rows.

---

## Dashboard

### `GET /api/dashboard/team`

**Supervisor only.** Returns one row per direct report for the calling supervisor. If the caller has no `manager_id` mappings, falls back to all active non-supervisor employees.

```json
[
  {
    "employee_id": 7,
    "employee_name": "Will Mason",
    "employee_email": "wmason@presidio.com",
    "green_count": 3,
    "amber_count": 1,
    "red_count": 0,
    "total_active_projects": 4
  }
]
```

### `GET /api/dashboard/me`

Any authenticated user. Returns projects owned by the caller (matched on `claims.preferred_username`).

---

## Reports

### `GET /api/reports/{id}`

Full report detail including milestones, blockers, and supervisor notes. Non-supervisors may only read their own reports.

```json
{
  "id": 118,
  "project_id": 42,
  "project_name": "AVS Refresh — FY26",
  "employee_id": 7,
  "employee_name": "Will Mason",
  "employee_email": "wmason@presidio.com",
  "submission_at": "2026-04-10T17:22:00",
  "rag_status": "AMBER",
  "rag_rationale": "Customer change request slipping critical path by 1 week.",
  "total_hours_budget": 240.0,
  "hours_consumed": 164.5,
  "pct_hours_consumed": 68.5,
  "reporting_period_start": "2026-04-01",
  "reporting_period_end": "2026-04-10",
  "narrative_summary": "…",
  "parse_confidence": 0.91,
  "needs_review": false,
  "milestones": [{ "id": 1, "description": "…", "completed": true, "due_date": "2026-04-05" }],
  "blockers":   [{ "id": 1, "description": "…", "severity": "MEDIUM", "is_resolved": false }],
  "notes":      [{ "id": 1, "note_text": "confirmed", "created_at": "…", "supervisor_name": "Will" }]
}
```

### `GET /api/reports/{id}/pptx`

302 redirect to a user-delegation SAS URL (30-min TTL) for the original PPTX blob. Same auth rule as `GET /api/reports/{id}`.

### `POST /api/reports/{id}/notes`

**Supervisor only.** Append a note to a report.

Request:
```json
{ "note_text": "Confirmed with customer on 4/11." }
```

Response:
```json
{ "id": 17 }
```

### `POST /api/reports/{id}/confirm`

**Supervisor only.** Clears `needs_review` on a report. Empty body.

### `POST /api/reports/{id}/correct`

**Supervisor only.** Patch any subset of extracted fields; also clears `needs_review`.

Request (all fields optional):
```json
{
  "project_name": "AVS Refresh FY26",
  "customer_name": "Acme Corp",
  "rag_status": "GREEN",
  "rag_rationale": "Change request pulled back in.",
  "total_hours_budget": 240.0,
  "hours_consumed": 170.0,
  "narrative_summary": "Back on track."
}
```

Fields that name the project/customer also update the parent `projects` row.

---

## Search

### `GET /api/search?q=<text>`

Any authenticated user. Minimum 2 characters. Returns three grouped lists with up to 25 rows each:

```json
{
  "projects": [{ "project_id": 42, "project_name": "…", "customer_name": "…" }],
  "reports":  [{ "id": 118, "project_id": 42, "project_name": "…", "submission_at": "…", "rag_status": "AMBER", "narrative_summary": "…" }],
  "blockers": [{ "id": 1, "report_id": 118, "project_name": "…", "description": "…", "severity": "MEDIUM" }]
}
```
