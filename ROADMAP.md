# ORBIT Roadmap

**Status:** Phase 0 complete (scaffolded — April 2026). Ready to enter Phase 1 provisioning.
**Owner:** Will Mason · Presidio Network Solutions
**Spec:** [`ORBIT_CLAUDE_CODE_SPEC.md`](./ORBIT_CLAUDE_CODE_SPEC.md)

This roadmap tracks delivery against the four phases in Section 13 of the spec. Each phase lists concrete tasks, explicit owners, acceptance criteria, and the cut-over gate to the next phase.

---

## Phase 0 — Scaffold ✅ (this commit)

Everything below is in the repo and committed. No Azure resources provisioned yet; no secrets loaded; no real PPTX has been processed.

- [x] Bicep infrastructure template (`infra/main.bicep`)
- [x] Database DDL (`database/schema.sql`)
- [x] Function App skeleton with `orbit_parser` (blob trigger) and `orbit_api` (ASGI/FastAPI)
- [x] Logic App workflow templates (ingestor + notifier) in `logic_apps/`
- [x] React + Vite + Tailwind v4 + MSAL dashboard
- [x] README deploy walkthrough
- [x] Docs in `docs/` (architecture, data model, API, dev, ops)

**Gate to Phase 1:** Anthropic API key in hand, Azure subscription + RG ready, O365 shared mailbox `orbit@presidiorocks.com` provisioned.

---

## Phase 1 — Data Pipeline (Week 1–2)

**Goal:** A real PPTX emailed to the shared mailbox lands in SQL with parsed milestones, blockers, and RAG status. No dashboard yet.

### Provision

- [ ] `az group create --name rg-orbit-prod --location eastus2`
- [ ] Fill `infra/parameters.json` with `sqlAdminPassword` and `deployerObjectId`
- [ ] `az deployment group create` with `infra/main.bicep`
- [ ] Capture outputs: `functionAppName`, `storageAccountName`, `sqlServerFqdn`, `keyVaultName`
- [ ] `az keyvault secret set ANTHROPIC-API-KEY` (Bicep seeds a `REPLACE_ME` placeholder)
- [ ] Whitelist your current IP on the SQL firewall so `sqlcmd` can connect
- [ ] Deploy `database/schema.sql` via sqlcmd or Azure Data Studio
- [ ] Seed at least one supervisor row: `INSERT INTO dbo.employees (email, display_name, is_supervisor) VALUES (…, …, 1);`

### Wire the ingestor

- [ ] Open `logic-orbit-ingestor-prod` in the designer, paste `logic_apps/ingestor.workflow.json`
- [ ] Authorize the O365 connection (sign in as the service account that owns the shared mailbox)
- [ ] Authorize the Azure Blob connection (use the Function App's managed identity or an SAS)
- [ ] Set `allowedSenderDomain = presidio.com` in the workflow parameters
- [ ] Save + enable, then send a test email from `wmason@presidio.com` with a real deck

### Deploy the parser

- [ ] `cd functions && func azure functionapp publish func-orbit-prod --python`
- [ ] Tail App Insights traces and confirm:
  - blob trigger fired
  - sidecar JSON loaded
  - `python-pptx` extraction succeeded
  - Claude agent returned parseable JSON
  - SQL upserts succeeded
- [ ] Verify the employee, project, status_report, milestones, and blockers rows all landed

### Acceptance (Phase 1 exits when…)

- [ ] Three test PPTX files (standard, non-standard, image-heavy) parse without manual fixes
- [ ] Project auto-creation + fuzzy matching behaves correctly on a second submission with a slightly different project name
- [ ] `needs_review = 1` correctly flags low-confidence parses
- [ ] Blob lifecycle policy is visible on the storage account

---

## Phase 2 — API + Notifications (Week 2–3)

**Goal:** The FastAPI surface is reachable with a valid bearer token and the notifier Logic App sends RED + low-confidence alerts.

### Entra ID

- [ ] Portal → Entra ID → App registrations → New: `orbit-dashboard`
- [ ] SPA redirect URI: `https://app-orbit-dashboard-prod.azurewebsites.net`
- [ ] Expose an API → App ID URI: `api://orbit-dashboard`, scope: `access_as_user`
- [ ] Add app roles: `Supervisor`, `Engineer`
- [ ] Assign yourself (and co-supervisors) to the `Supervisor` role under Enterprise Applications
- [ ] Record `clientId` + `tenantId` for the dashboard build

### API testing

- [ ] Confirm `GET /api/health` returns 200 anonymously
- [ ] Acquire a token for `api://orbit-dashboard/access_as_user` via `az account get-access-token` or a Postman OAuth2 flow
- [ ] Walk through every endpoint in `docs/api.md` with the token attached
- [ ] `GET /api/reports/{id}/pptx` returns a 302 to a valid 30-minute SAS URL

### Notifier

- [ ] Paste `logic_apps/notifier.workflow.json` into `logic-orbit-notifier-prod`
- [ ] Authorize O365 send-as permission for the shared mailbox
- [ ] Extend `functions/orbit_parser/__init__.py` to POST to the notifier trigger when:
  - `rag_status == "RED"`
  - `parse_confidence < 0.70`
  - `was_created` is true on the project match (new project alert)
  - employee `report_count == 1` (first-time sender alert)
- [ ] Verify each alert type fires end-to-end with a test submission

### Acceptance (Phase 2 exits when…)

- [ ] Every endpoint in `docs/api.md` passes a hand-executed smoke test under a Supervisor token
- [ ] Non-Supervisor tokens are correctly rejected on supervisor-only endpoints
- [ ] At least one of each alert type has been received in the supervisor inbox
- [ ] App Insights is logging requests, dependencies, and unhandled exceptions cleanly

---

## Phase 3 — Dashboard (Week 3–5)

**Goal:** Supervisors use the React dashboard end-to-end for real.

- [ ] `cd dashboard && npm install && npm run build`
- [ ] Write `dashboard/.env.production` with the Phase 2 `clientId`, `tenantId`, and API base URL
- [ ] Zip `dist/` and `az webapp deploy` to `app-orbit-dashboard-prod`
- [ ] Add SPA redirect URI to the app registration (already done in Phase 2, verify)
- [ ] Walk through the golden paths:
  - TeamOverview → EmployeeDetail → ProjectDetail
  - Confirm extraction on a low-confidence report
  - Add a supervisor note
  - Download the original PPTX via the SAS redirect
  - Global search across projects/reports/blockers
  - RAG trend chart on a project with ≥ 3 submissions
- [ ] Mobile-responsive pass on iPhone and iPad widths
- [ ] Dark mode is **not** in scope for Phase 3

### Acceptance (Phase 3 exits when…)

- [ ] Will + one co-supervisor have each driven the dashboard through a full reporting cycle
- [ ] At least one blocker was raised and resolved through the dashboard note flow
- [ ] No console errors in Edge, Chrome, or Safari
- [ ] Lighthouse accessibility score ≥ 90 on `/`, `/employees/:id`, `/projects/:id`

---

## Phase 4 — Polish + Go-Live (Week 5–6)

- [ ] Supervisor "Review queue" view (`?needs_review=true` filter) wired into the nav bar
- [ ] `POST /api/reports/{id}/correct` surfaced from the dashboard (inline edit on ProjectDetail)
- [ ] App Insights alert rules:
  - parser failures in the last 15 minutes > 0
  - RED status volume spike (> 3 in 24h across the team)
  - parse_confidence < 0.5 > 2 in 24h
- [ ] README onboarding copy reviewed with at least two engineers pre-launch
- [ ] Cutover announcement email drafted + sent to the engineering team
- [ ] Spec marked "LIVE" and this ROADMAP moved into Phase 5 (post-launch)

---

## Phase 5 — Post-Launch (deferred)

Things the spec explicitly pushes to later:

- Engineer dashboard access via Entra B2B guest invitations (presidio.com users)
- Sync to external PM tools (currently: ORBIT is system of record)
- Multi-org support — the `domain` column on `employees` is reserved for this
- Historical batch re-parse once Claude model gets upgraded (raw email bodies + blobs are retained for 2 years)

---

## Known Risks

| # | Risk | Mitigation |
|---|---|---|
| 1 | Cross-tenant mail flow to `orbit@presidiorocks.com` from `presidio.com` silently drops | Test with a throwaway `presidio.com` account before announcing |
| 2 | python-pptx can't read a heavily-styled exec-deck template | Document Intelligence fallback is wired; keep the 20-char heuristic in `doc_intelligence.py` under review |
| 3 | Claude returns invalid JSON on adversarial input | `claude_agent.py` already degrades to a confidence=0 stub; `needs_review` surfaces it to the supervisor |
| 4 | Supervisor not mapped as `manager_id` on any employee → `vw_team_rag_summary` returns empty | `dashboard.py` falls back to "all active reporters"; add explicit seeding to Phase 1 Day-1 checklist |
| 5 | Flex Consumption cold start on the parser delays first submission of the day | Acceptable for internal tool; revisit if > 60s |
