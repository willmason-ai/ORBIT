# Data Model

DDL lives in [`../database/schema.sql`](../database/schema.sql). This document is the narrative.

## The `employees` table (unified `reporters`)

The spec defined a `reporters` table, but its FKs and views both referenced an undefined `employees` table with a `manager_id` column. We unified them. The table is named **`employees`** and carries both identities:

| Column | Purpose |
|---|---|
| `email` | unique identity; populated from the inbound `From:` header |
| `display_name` / `full_name` | parsed from the sender display name; `full_name` is a computed fallback to `email` |
| `domain` | reserved for multi-org future (`presidio.com`, etc.) |
| `manager_id` | self-FK pointing at a supervisor row; drives `vw_team_rag_summary` |
| `is_supervisor` | boolean flag — set to 1 for seeded supervisors or auto-set when a supervisor first adds a note |
| `report_count` | incremented on every submission, surfaced in the dashboard |
| `first_seen` / `last_seen` | silent enrollment metrics |
| `entra_object_id` | reserved for Phase 2 B2B guest mapping |

**Why this matters:** both "engineer who sent an email" and "supervisor who logs into the dashboard" are rows in this one table. The discriminator is `is_supervisor`. The supervisor rollup view filters on `mgr.is_supervisor = 1 AND emp.is_active = 1`.

## `projects`

Auto-created on first mention of a project name. Fuzzy matching (`project_matcher.py`) uses `name_normalized` (lowercase/trim) with `difflib.get_close_matches(cutoff=0.85)` against active projects owned by the *same engineer*. No cross-owner matching — if two engineers report on a project with the same name, we get two project rows and a supervisor can merge manually.

## `status_reports`

One row per email submission. Important columns:

- `pct_hours_consumed` is a **PERSISTED computed column** so the dashboard can sort by it without a full scan
- `parse_confidence` is the Claude agent's self-assessment (0.0–1.0)
- `needs_review` is set to 1 whenever `parse_confidence < 0.70`
- `raw_agent_json` is the exact string the model returned, preserved for audit + future re-parse
- `blob_url` / `blob_path` point at the original PPTX — the URL is *without* SAS so it can safely serialize into logs; SAS is minted on-demand

## `milestones` and `blockers`

Always loaded alongside their parent report. Both have `ON DELETE CASCADE` so re-parsing a report via a future migration can cleanly drop and reinsert children.

## `supervisor_notes`

Append-only. No update/delete endpoint on the API — by design, notes are an audit trail.

## Full-text catalog

`orbit_ft` indexes:
- `projects(name, customer_name)`
- `status_reports(narrative_summary, rag_rationale, email_body_text)`
- `blockers(description)`

Phase 1 API uses `LIKE '%…%'` for portability; the catalog is in place so we can swap to `CONTAINS` / `FREETEXT` later without another migration.

## Views

### `vw_projects_latest`

One row per active project, joined to its most recent `status_reports` entry via `OUTER APPLY … TOP 1 ORDER BY submission_at DESC`. Used directly by:
- `/api/projects` (list + filter)
- `/api/projects/{id}` (detail header)
- `/api/employees/{id}/projects` (per-engineer list)
- `/api/dashboard/me` (engineer self-view)

### `vw_team_rag_summary`

One row per `(manager, direct-report)` pair with GREEN/AMBER/RED counts and `total_active_projects`. Used by `/api/dashboard/team`. If a supervisor has no `manager_id` mappings yet, the API falls back to "all active non-supervisor reporters" so the dashboard is never blank on day one.

## Evolution notes

- Adding columns to `status_reports`: safe; existing views don't `SELECT *`.
- Renaming `employees` back to `reporters` and adding a separate `supervisors` table: not recommended — the views would need a three-way join and gain nothing.
- Moving off Serverless: if auto-pause becomes a pain, bump to `GP_Gen5_2` provisioned — same DDL, no migration needed.
