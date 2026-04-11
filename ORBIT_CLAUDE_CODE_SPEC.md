# ORBIT — Operations Reporting & Brief Intelligence Tracker
## Claude Code Implementation Specification (FINAL)
**Author:** Will Mason | Presidio Network Solutions  
**Date:** April 10, 2026  
**Status:** READY FOR CLAUDE CODE — All decisions resolved

---

## Design Philosophy

> "Just send ORBIT the email."

Subordinates email a shared mailbox with their PPTX attached. That's it. No project codes in subject lines. No web forms. No special formatting required. The AI agent extracts everything — project name, hours, RAG status, milestones, blockers — and routes it to the right place automatically. The supervisor opens a dashboard and sees the full picture across their team.

---

## Resolved Decisions

| Decision | Choice | Notes |
|---|---|---|
| Email platform | Office 365 | Use Logic Apps O365 connector natively |
| PPTX template | AI handles any deck | Recommended template distributed but not enforced |
| Project matching | AI extracts name → auto-match or auto-create | Fuzzy match on project name; low-confidence = flagged for review |
| Email format | 1 email = 1 project, 1 PPTX | Engineers may send up to 8 emails/cycle if on 8 projects |
| Supervisor auth | Entra ID — presidiorocks.com tenant | Will + supervisors log in with presidiorocks.com credentials |
| Engineer identity | Email-only (presidio.com) | No dashboard login; profile auto-created from From: address |
| Engineer dashboard access | Phase 2 — supervisor-only for now | B2B guest access deferred; not in initial build |
| New reporter profile | Silent auto-create | No notification; profile appears in dashboard automatically |
| Blob retention | 2 years live → Azure Archive | Lifecycle policy on storage account, automatic |
| System of record | ORBIT only | No sync to external PM tools |
| Supervisor scale | 2–5 supervisors | presidiorocks.com tenant users with Supervisor app role |

---

## Cross-Tenant Identity Model

```
presidiorocks.com tenant          presidio.com domain
─────────────────────────         ──────────────────────────────
Will Mason (supervisor)           wmason@presidio.com (engineer)
  │                                 │
  │ Logs into dashboard             │ Sends email to
  │ via Entra ID SSO                │ orbit@presidiorocks.com
  │ (presidiorocks.com)             │
  ▼                                 ▼
ORBIT Dashboard               Logic App receives email
(supervisor-only, Phase 1)    extracts From: wmason@presidio.com
                                        │
                                        ▼
                              Reporter Profile auto-created:
                              {
                                email: "wmason@presidio.com",
                                full_name: "Will Mason",  ← parsed from email display name
                                domain: "presidio.com",
                                first_seen: <timestamp>,
                                report_count: 1
                              }
                                        │
                              All future emails from wmason@presidio.com
                              automatically linked to this profile.
```

**Key points:**
- The shared mailbox `orbit@presidiorocks.com` accepts external senders from `presidio.com` — this is default O365 behavior, no special config required
- Engineer identity is established 100% from the email `From:` header — no authentication, no enrollment, no action required from the engineer
- Display name is parsed from the email sender display name field (e.g. "Will Mason <wmason@presidio.com>") and stored on first submission; supervisor can edit if needed
- `domain` field on the reporter profile allows future filtering (e.g. if ORBIT expands to multiple orgs)
- Phase 2 engineer dashboard access would use Entra ID B2B guest invitations — presidio.com users log in with their existing presidio.com credentials, no new password needed

---

## 1. System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ORBIT — End-to-End Architecture                      │
└─────────────────────────────────────────────────────────────────────────┘

[Engineer]
    │
    │  Sends email to orbit@[org].com
    │  Subject: anything  ← no format required
    │  Attachment: project_status.pptx
    ▼
[Office 365 Shared Mailbox: orbit@[org].com]
    │
    │  Logic App Trigger: "When new email arrives (V3)"
    │  Filter: fetchOnlyWithAttachment = true
    │  Filter: sender must be in [org] domain (security)
    ▼
[Azure Logic App — orbit-ingestor]
    │
    ├── Validate: attachment is .pptx (reject others, send polite error reply)
    ├── Extract: sender email, timestamp, email body text
    ├── Upsert: employee record in SQL (create if first time)
    └── Upload PPTX to Blob: orbit-pptx-raw/{employee_id}/{yyyyMMdd_HHmmss}.pptx
         │
         │  Blob Created event
         ▼
    [Azure Function — orbit-parser]  Python 3.12, Flex Consumption
         │
         ├── Step 1: python-pptx extraction
         │     └── Text per shape, shape fill RGB (RAG colors), tables, slide titles
         │
         ├── Step 2: Azure AI Document Intelligence (Layout model)
         │     └── Fallback for image-heavy or scan-based slides
         │
         └── Step 3: Claude claude-sonnet-4-6 agent
               └── Input: all extracted slide text + color metadata + email body
               └── Output: validated JSON conforming to ProjectStatusReport schema
                    │
                    ▼
               [Azure SQL Database — orbitdb]
               Upsert project (fuzzy name match)
               Insert status_report, milestones, blockers
                    │
                    ▼
               [Azure Logic App — orbit-notifier]  (separate, lightweight)
               If rag_status = RED → email supervisor(s) alert
               If parse_confidence < 0.7 → email supervisor flagged for review
                    │
         ┌──────────┘
         │
         ▼
[FastAPI on Azure Functions — orbit-api]
    REST endpoints, Entra ID bearer token validation
         │
         ▼
[React Dashboard — Azure App Service B1]
    Entra ID SSO (MSAL.js)
    Supervisor: full team view
    Engineer: own projects only
```

---

## 2. Azure Resource Group

```
Resource Group: rg-orbit-prod  (East US 2 — consistent with your AVS/Foundry work)

├── Logic App:                    logic-orbit-ingestor
├── Logic App:                    logic-orbit-notifier
├── Storage Account:              storbitraw
│   └── Container:                orbit-pptx-raw
│       └── Lifecycle Policy:     Tier to Archive after 730 days
├── Azure AI Document Intelligence: docint-orbit (S0)
├── Azure SQL Server:             sql-orbit-prod
│   └── Database:                 orbitdb
│       Tier: Serverless GP_S_Gen5_1 (auto-pause after 1hr idle)
│       Backup: 7-day LRS
├── Function App:                 func-orbit  (Python 3.12, Flex Consumption)
│   ├── Function: orbit_parser    (Blob trigger)
│   └── Function: orbit_api       (HTTP — FastAPI ASGI)
├── App Service Plan:             asp-orbit-linux (B1, Linux)
├── App Service:                  app-orbit-dashboard
├── Key Vault:                    kv-orbit-prod
│   ├── Secret: ANTHROPIC-API-KEY
│   ├── Secret: SQL-CONNECTION-STRING
│   └── Secret: DOCINT-ENDPOINT + DOCINT-KEY
├── App Insights:                 appi-orbit-prod
├── Log Analytics Workspace:      law-orbit-prod
└── Entra ID App Registration:    orbit-dashboard
    ├── Redirect URI: https://app-orbit-dashboard.azurewebsites.net
    └── App Roles:
        ├── Supervisor  (can see all employees + all projects)
        └── Engineer    (can see only own submissions)
```

---

## 3. Database Schema

```sql
-- ============================================================
-- ORBIT Database Schema
-- Azure SQL Serverless GP_S_Gen5_1
-- ============================================================

-- Reporter Profiles (auto-created silently from inbound email From: address)
-- Identity established purely from presidio.com email — no login, no enrollment
CREATE TABLE reporters (
    id              INT IDENTITY PRIMARY KEY,
    email           NVARCHAR(255) NOT NULL UNIQUE,  -- e.g. wmason@presidio.com
    display_name    NVARCHAR(255),          -- parsed from email sender display name
    domain          NVARCHAR(100),          -- e.g. "presidio.com" (future multi-org support)
    report_count    INT DEFAULT 0,          -- incremented on each submission
    first_seen      DATETIME2 DEFAULT GETUTCDATE(),
    last_seen       DATETIME2 DEFAULT GETUTCDATE(),
    notes           NVARCHAR(MAX),          -- supervisor can add context (role, team, etc.)
    is_active       BIT DEFAULT 1,
    -- Phase 2: populated when B2B guest access is enabled
    entra_object_id NVARCHAR(100) NULL,
    created_at      DATETIME2 DEFAULT GETUTCDATE()
);

-- Projects (auto-created by AI agent on first mention, supervisor can edit)
CREATE TABLE projects (
    id              INT IDENTITY PRIMARY KEY,
    name            NVARCHAR(500) NOT NULL,
    name_normalized NVARCHAR(500),          -- lowercase, trimmed — used for fuzzy matching
    customer_name   NVARCHAR(500),
    owner_id        INT REFERENCES employees(id),
    start_date      DATE,
    target_end_date DATE,
    is_active       BIT DEFAULT 1,
    created_at      DATETIME2 DEFAULT GETUTCDATE(),
    updated_at      DATETIME2 DEFAULT GETUTCDATE()
);

-- Status Reports (one row per email submission)
CREATE TABLE status_reports (
    id                      INT IDENTITY PRIMARY KEY,
    project_id              INT REFERENCES projects(id),
    employee_id             INT REFERENCES employees(id),
    submission_at           DATETIME2 NOT NULL,
    rag_status              NVARCHAR(10) CHECK (rag_status IN ('RED','AMBER','GREEN')),
    rag_rationale           NVARCHAR(MAX),
    total_hours_budget      DECIMAL(10,2),
    hours_consumed          DECIMAL(10,2),
    pct_hours_consumed      AS (CASE WHEN total_hours_budget > 0
                                THEN CAST(hours_consumed/total_hours_budget*100 AS DECIMAL(5,1))
                                ELSE NULL END) PERSISTED,
    reporting_period_start  DATE,
    reporting_period_end    DATE,
    narrative_summary       NVARCHAR(MAX),
    email_body_text         NVARCHAR(MAX),  -- raw email body for context
    blob_url                NVARCHAR(1000), -- SAS URL to original PPTX
    blob_path               NVARCHAR(1000), -- internal path for lifecycle management
    parse_confidence        DECIMAL(3,2),   -- 0.00–1.00; <0.70 flags for supervisor review
    needs_review            BIT DEFAULT 0,  -- supervisor must confirm extracted data
    raw_agent_json          NVARCHAR(MAX),  -- full Claude output stored for audit/debug
    created_at              DATETIME2 DEFAULT GETUTCDATE()
);

-- Milestones (per status report)
CREATE TABLE milestones (
    id              INT IDENTITY PRIMARY KEY,
    report_id       INT REFERENCES status_reports(id) ON DELETE CASCADE,
    description     NVARCHAR(MAX) NOT NULL,
    completed       BIT DEFAULT 0,
    due_date        DATE
);

-- Blockers / Issues (per status report)
CREATE TABLE blockers (
    id              INT IDENTITY PRIMARY KEY,
    report_id       INT REFERENCES status_reports(id) ON DELETE CASCADE,
    description     NVARCHAR(MAX) NOT NULL,
    severity        NVARCHAR(10) CHECK (severity IN ('HIGH','MEDIUM','LOW')),
    is_resolved     BIT DEFAULT 0
);

-- Supervisor notes (supervisor can annotate any status report)
CREATE TABLE supervisor_notes (
    id              INT IDENTITY PRIMARY KEY,
    report_id       INT REFERENCES status_reports(id),
    supervisor_id   INT REFERENCES employees(id),
    note_text       NVARCHAR(MAX),
    created_at      DATETIME2 DEFAULT GETUTCDATE()
);

-- ============================================================
-- Full-Text Search
-- ============================================================
CREATE FULLTEXT CATALOG orbit_ft AS DEFAULT;

CREATE FULLTEXT INDEX ON projects(name, customer_name)
    KEY INDEX PK__projects__[auto];

CREATE FULLTEXT INDEX ON status_reports(narrative_summary, rag_rationale, email_body_text)
    KEY INDEX PK__status_reports__[auto];

CREATE FULLTEXT INDEX ON blockers(description)
    KEY INDEX PK__blockers__[auto];

-- ============================================================
-- Useful Views
-- ============================================================

-- Latest status per project (most recent submission only)
CREATE VIEW vw_projects_latest AS
SELECT
    p.id            AS project_id,
    p.name          AS project_name,
    p.customer_name,
    e.full_name     AS owner_name,
    e.email         AS owner_email,
    sr.rag_status,
    sr.pct_hours_consumed,
    sr.total_hours_budget,
    sr.hours_consumed,
    sr.submission_at AS last_updated,
    sr.needs_review,
    sr.id           AS latest_report_id
FROM projects p
JOIN employees e ON p.owner_id = e.id
JOIN status_reports sr ON sr.id = (
    SELECT TOP 1 id FROM status_reports
    WHERE project_id = p.id
    ORDER BY submission_at DESC
)
WHERE p.is_active = 1;

-- Team overview: each supervisor sees their direct reports and their RAG status summary
CREATE VIEW vw_team_rag_summary AS
SELECT
    mgr.id          AS manager_id,
    mgr.full_name   AS manager_name,
    emp.id          AS employee_id,
    emp.full_name   AS employee_name,
    emp.email       AS employee_email,
    COUNT(CASE WHEN v.rag_status = 'GREEN' THEN 1 END) AS green_count,
    COUNT(CASE WHEN v.rag_status = 'AMBER' THEN 1 END) AS amber_count,
    COUNT(CASE WHEN v.rag_status = 'RED'   THEN 1 END) AS red_count,
    COUNT(v.project_id) AS total_active_projects
FROM employees mgr
JOIN employees emp ON emp.manager_id = mgr.id
LEFT JOIN vw_projects_latest v ON v.owner_email = emp.email
GROUP BY mgr.id, mgr.full_name, emp.id, emp.full_name, emp.email;
```

---

## 4. Python: PPTX Extraction Module

**File:** `functions/orbit_parser/pptx_extractor.py`

```python
from pptx import Presentation
from pptx.util import Pt
from pptx.enum.dml import MSO_THEME_COLOR
import io

# RAG color reference values (RGB tuples)
RAG_COLORS = {
    "RED":   [(255,0,0),(192,0,0),(255,0,16),(196,15,38)],
    "AMBER": [(255,192,0),(255,255,0),(237,125,49),(255,165,0)],
    "GREEN": [(0,176,80),(112,173,71),(0,128,0),(0,176,240)],
}

def _color_distance(c1: tuple, c2: tuple) -> float:
    return sum((a-b)**2 for a,b in zip(c1,c2)) ** 0.5

def _rgb_to_rag(rgb: tuple, threshold: float = 70.0) -> str | None:
    best, best_dist = None, float("inf")
    for status, colors in RAG_COLORS.items():
        for ref in colors:
            d = _color_distance(rgb, ref)
            if d < best_dist:
                best_dist, best = d, status
    return best if best_dist <= threshold else None

def extract_pptx(file_bytes: bytes) -> dict:
    """
    Extract all text, table data, and color metadata from a PPTX file.
    Returns a dict ready to be passed to the Claude agent.
    """
    prs = Presentation(io.BytesIO(file_bytes))
    slides_out = []

    for slide_num, slide in enumerate(prs.slides, 1):
        slide_data = {
            "slide_number": slide_num,
            "slide_title": None,
            "shapes": [],
            "tables": [],
        }

        # Try to get slide title
        if slide.shapes.title:
            slide_data["slide_title"] = slide.shapes.title.text.strip()

        for shape in slide.shapes:
            # Extract fill color
            rgb, rag_hint = None, None
            try:
                fill = shape.fill
                if fill.type == 1:  # MSO_FILL.SOLID
                    rgb_obj = fill.fore_color.rgb
                    rgb = (rgb_obj.r, rgb_obj.g, rgb_obj.b)
                    rag_hint = _rgb_to_rag(rgb)
            except Exception:
                pass

            # Extract text
            text = ""
            if shape.has_text_frame:
                text = "\n".join(
                    p.text for p in shape.text_frame.paragraphs if p.text.strip()
                )

            # Extract table
            if shape.has_table:
                table_data = []
                for row in shape.table.rows:
                    table_data.append([cell.text.strip() for cell in row.cells])
                slide_data["tables"].append({
                    "shape_name": shape.name,
                    "rows": table_data
                })

            if text or rag_hint:
                slide_data["shapes"].append({
                    "shape_name": shape.name,
                    "text": text,
                    "fill_rgb": rgb,
                    "rag_hint": rag_hint,
                })

        slides_out.append(slide_data)

    return {
        "slide_count": len(prs.slides),
        "slides": slides_out,
    }
```

---

## 5. Claude Agent Module

**File:** `functions/orbit_parser/claude_agent.py`

```python
import anthropic
import json
import re

client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY from env / Key Vault ref

SYSTEM_PROMPT = """
You are ORBIT's project status extraction agent.
You receive raw text and color metadata extracted from a PowerPoint status report
submitted by an engineer. Your job is to return a single JSON object conforming
exactly to the schema below. Do not add markdown. Do not add commentary.
Return ONLY the JSON object.

OUTPUT SCHEMA:
{
  "project_name": "string — exact name of the project",
  "customer_name": "string or null",
  "total_hours_budgeted": number_or_null,
  "hours_consumed": number_or_null,
  "rag_status": "RED" or "AMBER" or "GREEN" or null,
  "rag_rationale": "string — why this status, in 1–2 sentences, or null",
  "reporting_period": {
    "start": "YYYY-MM-DD or null",
    "end": "YYYY-MM-DD or null"
  },
  "milestones": [
    { "description": "string", "completed": true_or_false, "due_date": "YYYY-MM-DD or null" }
  ],
  "blockers": [
    { "description": "string", "severity": "HIGH" or "MEDIUM" or "LOW" or null }
  ],
  "narrative_summary": "string — 2–3 sentence plain English summary of overall status, or null",
  "parse_confidence": 0.0_to_1.0
}

EXTRACTION RULES:
1. RAG STATUS — check in this order:
   a. Color hints in the slide data: rag_hint = RED → "RED", AMBER → "AMBER", GREEN → "GREEN"
   b. Text labels: "ON TRACK" or "GREEN" → GREEN; "AT RISK" or "AMBER" or "WATCH" → AMBER;
      "CRITICAL" or "OFF TRACK" or "RED" or "BEHIND" → RED
   c. If ambiguous, use the most prominent colored shape on what appears to be a status slide.

2. HOURS — look for any of these patterns:
   "X of Y hours", "Budget: Y / Consumed: X", "X hrs consumed", "X/Y hrs",
   percentages like "65% complete" combined with a total budget elsewhere.

3. MILESTONES — look for slides/sections titled "Milestones", "Accomplishments",
   "Progress", "Schedule". Completed items often have: checkmarks (✅ ✓), 
   strikethrough text, or explicit "Complete" / "Done" labels.
   Upcoming items may have: ⏳, future dates, "In Progress", "Planned".

4. BLOCKERS — look for slides/sections titled "Issues", "Risks", "Problems",
   "Impediments", "Blockers", "Challenges". Rate severity:
   HIGH = blocking delivery or requiring immediate escalation
   MEDIUM = impacting schedule but workaround exists
   LOW = minor, informational only

5. parse_confidence — your honest estimate (0.0–1.0) of how confident you are
   in the extraction. Set below 0.70 if:
   - project name is ambiguous or missing
   - no clear RAG signal found
   - hours data is absent
   - slide content appears to be a generic or non-status deck

Return null for any field you cannot extract with reasonable confidence.
Never fabricate data.
"""

def extract_project_status(
    pptx_data: dict,
    email_body: str,
    sender_email: str,
) -> dict:
    """
    Call Claude to extract structured project status from PPTX extraction output.
    Returns the parsed JSON dict.
    """
    # Build the user message
    user_content = f"""
SENDER: {sender_email}

EMAIL BODY:
{email_body or "(no email body text)"}

POWERPOINT EXTRACTION ({pptx_data['slide_count']} slides):
{json.dumps(pptx_data['slides'], indent=2)}
"""

    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=2000,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_content}],
    )

    raw_text = response.content[0].text.strip()

    # Strip any accidental markdown fences
    raw_text = re.sub(r"^```json\s*", "", raw_text)
    raw_text = re.sub(r"\s*```$", "", raw_text)

    result = json.loads(raw_text)

    # Enforce minimum confidence flag
    result["needs_review"] = result.get("parse_confidence", 1.0) < 0.70

    return result
```

---

## 6. FastAPI Endpoints

**File:** `functions/orbit_api/__init__.py`

```
GET  /api/health                          — liveness check

# Projects
GET  /api/projects                        — list active projects
     ?search=<text>                       — full-text search
     ?rag=RED|AMBER|GREEN                 — filter by status
     ?employee_id=<int>                   — filter by owner
     ?needs_review=true                   — supervisor review queue
GET  /api/projects/{id}                   — project detail + latest report
GET  /api/projects/{id}/history           — all reports for project (RAG trend data)

# Employees
GET  /api/employees                       — list employees
GET  /api/employees/{id}                  — employee detail
GET  /api/employees/{id}/projects         — all active projects for employee

# Dashboard
GET  /api/dashboard/team                  — supervisor overview
     Returns: each employee + their RAG counts + project list
     Auth: Supervisor role only

GET  /api/dashboard/me                    — engineer's own projects
     Auth: any authenticated user

# Reports
GET  /api/reports/{id}                    — full report detail (milestones + blockers)
GET  /api/reports/{id}/pptx               — redirect to blob SAS URL (30-min expiry)
POST /api/reports/{id}/notes              — supervisor adds note to a report
POST /api/reports/{id}/confirm            — supervisor confirms AI extraction is correct
                                            (clears needs_review flag)
POST /api/reports/{id}/correct            — supervisor submits corrections to extracted data

# Search
GET  /api/search?q=<text>                 — full-text across projects, blockers, narratives
     Returns: { projects: [], reports: [], blockers: [] }
```

---

## 7. Claude Agent: Project Name Matching Logic

Since there's no project code in the email, the system uses fuzzy matching to tie a new submission to an existing project record.

```python
# functions/orbit_parser/project_matcher.py

import difflib

def find_or_create_project(
    extracted_name: str,
    customer_name: str | None,
    employee_id: int,
    db_conn,
    confidence_threshold: float = 0.85,
) -> tuple[int, bool]:
    """
    Returns (project_id, was_created).
    If a close match is found (similarity >= threshold), link to it.
    Otherwise, create a new project record.
    """
    normalized = extracted_name.lower().strip()

    # Fetch active projects owned by this employee
    existing = db_conn.execute("""
        SELECT id, name_normalized FROM projects
        WHERE owner_id = ? AND is_active = 1
    """, employee_id).fetchall()

    if existing:
        names = [row.name_normalized for row in existing]
        matches = difflib.get_close_matches(
            normalized, names, n=1, cutoff=confidence_threshold
        )
        if matches:
            matched_row = next(r for r in existing if r.name_normalized == matches[0])
            return matched_row.id, False

    # No match — create new project
    result = db_conn.execute("""
        INSERT INTO projects (name, name_normalized, customer_name, owner_id)
        OUTPUT INSERTED.id
        VALUES (?, ?, ?, ?)
    """, extracted_name, normalized, customer_name, employee_id)

    return result.fetchone().id, True
```

---

## 8. Notification Logic

**Triggers for supervisor notification email (via second Logic App):**

| Condition | Action |
|---|---|
| `rag_status = RED` | Email all supervisors: "🔴 RED status reported — {project_name} by {engineer_name}" |
| `parse_confidence < 0.70` | Email supervisors: "⚠️ ORBIT needs your review — low-confidence parse for {engineer_name}" |
| New project auto-created | Email supervisors: "📁 New project detected — {project_name} by {engineer_name}. Please confirm." |
| First submission from new engineer | Email supervisors: "👤 New engineer registered — {engineer_name}" |

---

## 9. React Dashboard Spec

### Component Tree

```
App
├── AuthProvider (MSAL)
├── NavBar
│   ├── Logo + "ORBIT"
│   ├── GlobalSearchBar → /SearchView
│   └── UserMenu (Entra ID name + avatar)
│
├── /  → TeamOverview (Supervisor role)
│   └── EmployeeCard[]
│       ├── Avatar / initials
│       ├── Name + email
│       └── RAGSummaryChips  (🟢2 🟡1 🔴0)
│           └── onClick → EmployeeDetail
│
├── /employees/:id  → EmployeeDetail
│   ├── EmployeeHeader
│   └── ProjectCard[]
│       ├── ProjectName + CustomerName
│       ├── RAGBadge
│       ├── HoursProgressBar  (consumed / budgeted)
│       └── LastUpdated timestamp
│           └── onClick → ProjectDetail
│
├── /projects/:id  → ProjectDetail
│   ├── ProjectHeader (name, customer, owner, RAGBadge)
│   ├── HoursGauge  (circular or bar)
│   ├── Tabs:
│   │   ├── Milestones  → MilestoneList (✅ completed, ⏳ pending)
│   │   ├── Blockers    → BlockerList (severity color-coded)
│   │   └── History     → RAGTrendChart + SubmissionTimeline
│   ├── NarrativeCard  (AI summary text)
│   ├── SupervisorNotes (add/view notes)
│   ├── [Supervisor only] ConfirmExtraction button
│   └── DownloadPPTX button
│
├── /search?q=  → SearchView
│   ├── SearchBar (pre-filled)
│   └── Results grouped: Projects | Reports | Blockers
│
└── /me  → MyProjects (Engineer role — own projects only)
    └── same as EmployeeDetail but for current user
```

### Tech Stack

```json
{
  "framework": "React 18 + TypeScript",
  "build": "Vite 5",
  "styling": "Tailwind CSS v4",
  "auth": "MSAL.js v3 (@azure/msal-react)",
  "http": "Axios",
  "charts": "Recharts",
  "icons": "Lucide React",
  "routing": "React Router v6",
  "hosting": "Azure App Service B1 Linux"
}
```

### RAG Color System (Tailwind)

```typescript
// src/lib/rag.ts
export const RAG = {
  RED:   { bg: "bg-red-100",    border: "border-red-500",    text: "text-red-700",    label: "RED",   emoji: "🔴" },
  AMBER: { bg: "bg-amber-100",  border: "border-amber-500",  text: "text-amber-700",  label: "AMBER", emoji: "🟡" },
  GREEN: { bg: "bg-green-100",  border: "border-green-500",  text: "text-green-700",  label: "GREEN", emoji: "🟢" },
} as const;
```

---

## 10. Infrastructure as Code (Bicep) — Key Resources

**File:** `infra/main.bicep`

Claude Code should generate full Bicep for:

```bicep
// Resources to provision:
// 1. Resource Group (or assume existing)
// 2. Storage Account (LRS) + Container + Lifecycle Policy (Archive after 730 days)
// 3. Azure AI Document Intelligence (S0)
// 4. Azure SQL Server + Database (Serverless GP_S_Gen5_1, auto-pause 60 min)
// 5. Key Vault (Standard) + secrets (empty placeholders)
// 6. App Insights + Log Analytics Workspace
// 7. Function App (Flex Consumption, Python 3.12)
//    - System-assigned Managed Identity
//    - Key Vault references for secrets
//    - App settings: ANTHROPIC_API_KEY (KV ref), SQL_CONNECTION_STRING (KV ref)
// 8. Logic App (Consumption) — orbit-ingestor
// 9. Logic App (Consumption) — orbit-notifier
// 10. App Service Plan (B1 Linux) + App Service (Node 20 for React build)
// 11. Entra ID App Registration (manual — document steps, can't Bicep this)

// Managed Identity role assignments:
// - Function App MI → Storage Blob Data Contributor on storbitraw
// - Function App MI → Key Vault Secrets User on kv-orbit-prod
// - Logic App MI  → Storage Blob Data Contributor on storbitraw
// - Logic App MI  → Key Vault Secrets User on kv-orbit-prod
```

---

## 11. Environment Variables / App Settings

```bash
# Function App Settings (sourced from Key Vault via KV references)
ANTHROPIC_API_KEY           = @Microsoft.KeyVault(...)
SQL_CONNECTION_STRING       = @Microsoft.KeyVault(...)
DOCINT_ENDPOINT             = @Microsoft.KeyVault(...)
DOCINT_KEY                  = @Microsoft.KeyVault(...)

# Non-secret settings (set directly)
BLOB_CONTAINER_NAME         = orbit-pptx-raw
STORAGE_ACCOUNT_NAME        = storbitraw
PARSE_CONFIDENCE_THRESHOLD  = 0.70
PROJECT_MATCH_THRESHOLD     = 0.85
SUPERVISOR_EMAILS           = will@org.com,supervisor2@org.com
ORBIT_ENV                   = production
```

---

## 12. File Structure for Claude Code

```
orbit/
├── ORBIT_CLAUDE_CODE_SPEC.md     ← this file
├── infra/
│   ├── main.bicep
│   └── parameters.json
├── functions/                    ← Single Function App, two functions
│   ├── requirements.txt
│   ├── function_app.py           ← AsgiFunctionApp entry point
│   ├── host.json
│   ├── orbit_parser/
│   │   ├── __init__.py           ← Blob trigger handler (orchestrates steps 1–3)
│   │   ├── pptx_extractor.py     ← python-pptx extraction
│   │   ├── doc_intelligence.py   ← Azure AI DI integration (fallback)
│   │   ├── claude_agent.py       ← Claude API call + JSON validation
│   │   ├── project_matcher.py    ← Fuzzy project name matching
│   │   └── db.py                 ← SQL upsert logic (pyodbc)
│   └── orbit_api/
│       ├── __init__.py           ← FastAPI app definition
│       ├── auth.py               ← Entra ID bearer token validation
│       ├── routers/
│       │   ├── projects.py
│       │   ├── employees.py
│       │   ├── reports.py
│       │   ├── dashboard.py
│       │   └── search.py
│       └── models.py             ← Pydantic request/response schemas
├── database/
│   └── schema.sql                ← Full DDL (from Section 3)
├── dashboard/                    ← React app
│   ├── package.json
│   ├── vite.config.ts
│   ├── tailwind.config.ts
│   ├── index.html
│   └── src/
│       ├── main.tsx
│       ├── App.tsx
│       ├── lib/
│       │   ├── rag.ts
│       │   ├── api.ts            ← Axios client (attaches Entra ID token)
│       │   └── auth.ts           ← MSAL config
│       ├── components/
│       │   ├── NavBar.tsx
│       │   ├── RAGBadge.tsx
│       │   ├── HoursGauge.tsx
│       │   ├── MilestoneList.tsx
│       │   ├── BlockerList.tsx
│       │   └── RAGTrendChart.tsx
│       └── pages/
│           ├── TeamOverview.tsx
│           ├── EmployeeDetail.tsx
│           ├── ProjectDetail.tsx
│           ├── SearchView.tsx
│           └── MyProjects.tsx
└── README.md                     ← Setup + deployment steps
```

---

## 13. Implementation Phases

### Phase 1 — Data Pipeline (Week 1–2)
- [ ] Provision Azure resources via Bicep
- [ ] Create shared mailbox: `orbit@[org].com` in O365 admin
- [ ] Deploy `schema.sql` to orbitdb
- [ ] Build Logic App: email trigger → attachment filter → blob upload
- [ ] Build `orbit_parser` function: pptx_extractor + claude_agent + db write
- [ ] Test with 3 sample PPTX files (standard, non-standard, image-heavy)
- [ ] Validate project auto-create and fuzzy matching

### Phase 2 — API (Week 2–3)
- [ ] Build FastAPI routes (projects, employees, dashboard, search)
- [ ] Add Entra ID token validation middleware
- [ ] Test all endpoints with Postman / built-in `/docs`
- [ ] Wire orbit-notifier Logic App (RED alert + low-confidence alert)

### Phase 3 — Dashboard (Week 3–5)
- [ ] Scaffold React app (Vite + Tailwind + MSAL)
- [ ] Build TeamOverview → EmployeeDetail → ProjectDetail flow
- [ ] Build SearchView
- [ ] Add HoursGauge and RAGTrendChart (Recharts)
- [ ] Deploy to App Service, configure MSAL redirect URIs
- [ ] Supervisor role vs. Engineer role testing

### Phase 4 — Polish (Week 5–6)
- [ ] Supervisor note adding + extraction confirmation flow
- [ ] PPTX download via SAS URL
- [ ] Mobile-responsive layout
- [ ] App Insights alerting (parse failures, RED status volume spike)
- [ ] README: deployment guide + engineer onboarding instructions

---

## 14. Cost Estimate (Monthly, Production)

| Service | Tier | Est. Cost |
|---|---|---|
| Logic Apps (ingestor + notifier) | Consumption | ~$0.50 |
| Blob Storage (~10 GB, LRS) | Hot tier | ~$0.25 |
| Azure AI Document Intelligence | S0 (~200 pages/mo) | ~$3.00 |
| Azure SQL Database | Serverless GP_S_Gen5_1 | ~$15–30 |
| Azure Functions (parser + API) | Flex Consumption | ~$2–5 |
| App Service (dashboard) | B1 Linux | ~$13 |
| Key Vault | Standard | ~$0.10 |
| App Insights + Log Analytics | Pay-per-use | ~$2–5 |
| Anthropic Claude API | Sonnet 4.6, ~50 PPTX/mo | ~$3–10 |
| **Total** | | **~$39–67/month** |

---

*ORBIT Spec v1.1 — All decisions resolved. Ready for Claude Code.*  
*Start with: `infra/main.bicep` → `database/schema.sql` → `functions/orbit_parser/` → `functions/orbit_api/` → `dashboard/`*
