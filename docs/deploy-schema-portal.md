# Deploying the ORBIT Schema via Azure Portal Query Editor

## Prerequisites

- Access to the Azure Portal with permissions on `sql-avsnetmon` in `rg-avs2`
- The SQL admin password: stored in `kv-orbit-wmason` as `SQL-CONNECTION-STRING` (or you already know it)

## Steps

### 1. Open the Query Editor

1. Go to the [Azure Portal](https://portal.azure.com)
2. Navigate to **Resource Group** → `rg-avs2` → `sql-avsnetmon` (SQL server)
3. In the left sidebar, click **SQL databases** → `orbitdb`
4. In the left sidebar under the database, click **Query editor (preview)**

### 2. Sign In

- **Authentication type:** SQL Server authentication
- **Login:** `avsnetmon_admin`
- **Password:** `Csu^kgzMxH3ZvEGomoeB%UWr`
- Click **OK**

> If you get a firewall error, the portal will offer to add your client IP automatically — click **Set server firewall** and add it, then retry the login.

### 3. Run the Schema — Batch by Batch

The Query Editor does **not** support `GO` batch separators. You need to run each batch separately. Copy and paste each block below into the editor, then click **Run** after each one.

---

**Batch 1 — Employees table**

```sql
IF OBJECT_ID('dbo.employees', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.employees (
        id              INT IDENTITY PRIMARY KEY,
        email           NVARCHAR(255) NOT NULL UNIQUE,
        display_name    NVARCHAR(255),
        full_name       AS (ISNULL(display_name, email)) PERSISTED,
        domain          NVARCHAR(100),
        manager_id      INT NULL REFERENCES dbo.employees(id),
        report_count    INT NOT NULL DEFAULT 0,
        first_seen      DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        last_seen       DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        notes           NVARCHAR(MAX),
        is_active       BIT NOT NULL DEFAULT 1,
        is_supervisor   BIT NOT NULL DEFAULT 0,
        entra_object_id NVARCHAR(100) NULL,
        created_at      DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    CREATE INDEX ix_employees_manager ON dbo.employees(manager_id);
    CREATE INDEX ix_employees_domain  ON dbo.employees(domain);
END
```

---

**Batch 2 — Projects table**

```sql
IF OBJECT_ID('dbo.projects', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.projects (
        id              INT IDENTITY PRIMARY KEY,
        name            NVARCHAR(500) NOT NULL,
        name_normalized NVARCHAR(500),
        customer_name   NVARCHAR(500),
        owner_id        INT REFERENCES dbo.employees(id),
        start_date      DATE,
        target_end_date DATE,
        is_active       BIT NOT NULL DEFAULT 1,
        created_at      DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        updated_at      DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    CREATE INDEX ix_projects_owner      ON dbo.projects(owner_id);
    CREATE INDEX ix_projects_normalized ON dbo.projects(name_normalized);
END
```

---

**Batch 3 — Status Reports table**

```sql
IF OBJECT_ID('dbo.status_reports', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.status_reports (
        id                      INT IDENTITY PRIMARY KEY,
        project_id              INT REFERENCES dbo.projects(id),
        employee_id             INT REFERENCES dbo.employees(id),
        submission_at           DATETIME2 NOT NULL,
        rag_status              NVARCHAR(10) CHECK (rag_status IN ('RED','AMBER','GREEN')),
        rag_rationale           NVARCHAR(MAX),
        total_hours_budget      DECIMAL(10,2),
        hours_consumed          DECIMAL(10,2),
        pct_hours_consumed      AS (CASE WHEN total_hours_budget > 0
                                         THEN CAST(hours_consumed / total_hours_budget * 100 AS DECIMAL(5,1))
                                         ELSE NULL END) PERSISTED,
        reporting_period_start  DATE,
        reporting_period_end    DATE,
        narrative_summary       NVARCHAR(MAX),
        email_body_text         NVARCHAR(MAX),
        blob_url                NVARCHAR(1000),
        blob_path               NVARCHAR(1000),
        parse_confidence        DECIMAL(3,2),
        needs_review            BIT NOT NULL DEFAULT 0,
        raw_agent_json          NVARCHAR(MAX),
        created_at              DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    CREATE INDEX ix_reports_project    ON dbo.status_reports(project_id, submission_at DESC);
    CREATE INDEX ix_reports_employee   ON dbo.status_reports(employee_id, submission_at DESC);
    CREATE INDEX ix_reports_review     ON dbo.status_reports(needs_review) WHERE needs_review = 1;
END
```

---

**Batch 4 — Milestones table**

```sql
IF OBJECT_ID('dbo.milestones', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.milestones (
        id              INT IDENTITY PRIMARY KEY,
        report_id       INT NOT NULL REFERENCES dbo.status_reports(id) ON DELETE CASCADE,
        description     NVARCHAR(MAX) NOT NULL,
        completed       BIT NOT NULL DEFAULT 0,
        due_date        DATE
    );
    CREATE INDEX ix_milestones_report ON dbo.milestones(report_id);
END
```

---

**Batch 5 — Blockers table**

```sql
IF OBJECT_ID('dbo.blockers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.blockers (
        id              INT IDENTITY PRIMARY KEY,
        report_id       INT NOT NULL REFERENCES dbo.status_reports(id) ON DELETE CASCADE,
        description     NVARCHAR(MAX) NOT NULL,
        severity        NVARCHAR(10) CHECK (severity IN ('HIGH','MEDIUM','LOW')),
        is_resolved     BIT NOT NULL DEFAULT 0
    );
    CREATE INDEX ix_blockers_report ON dbo.blockers(report_id);
END
```

---

**Batch 6 — Supervisor Notes table**

```sql
IF OBJECT_ID('dbo.supervisor_notes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.supervisor_notes (
        id              INT IDENTITY PRIMARY KEY,
        report_id       INT NOT NULL REFERENCES dbo.status_reports(id) ON DELETE CASCADE,
        supervisor_id   INT NOT NULL REFERENCES dbo.employees(id),
        note_text       NVARCHAR(MAX) NOT NULL,
        created_at      DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    CREATE INDEX ix_notes_report ON dbo.supervisor_notes(report_id);
END
```

---

**Batch 7 — Full-Text Catalog**

```sql
IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = 'orbit_ft')
    CREATE FULLTEXT CATALOG orbit_ft AS DEFAULT;
```

---

**Batch 8 — Full-Text Index on Projects**

```sql
IF NOT EXISTS (
    SELECT 1 FROM sys.fulltext_indexes
    WHERE object_id = OBJECT_ID('dbo.projects')
)
BEGIN
    DECLARE @pk_projects NVARCHAR(256) =
        (SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.projects') AND is_primary_key = 1);
    EXEC('CREATE FULLTEXT INDEX ON dbo.projects(name, customer_name) KEY INDEX ' + @pk_projects + ' ON orbit_ft;');
END
```

---

**Batch 9 — Full-Text Index on Status Reports**

```sql
IF NOT EXISTS (
    SELECT 1 FROM sys.fulltext_indexes
    WHERE object_id = OBJECT_ID('dbo.status_reports')
)
BEGIN
    DECLARE @pk_reports NVARCHAR(256) =
        (SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.status_reports') AND is_primary_key = 1);
    EXEC('CREATE FULLTEXT INDEX ON dbo.status_reports(narrative_summary, rag_rationale, email_body_text) KEY INDEX ' + @pk_reports + ' ON orbit_ft;');
END
```

---

**Batch 10 — Full-Text Index on Blockers**

```sql
IF NOT EXISTS (
    SELECT 1 FROM sys.fulltext_indexes
    WHERE object_id = OBJECT_ID('dbo.blockers')
)
BEGIN
    DECLARE @pk_blockers NVARCHAR(256) =
        (SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.blockers') AND is_primary_key = 1);
    EXEC('CREATE FULLTEXT INDEX ON dbo.blockers(description) KEY INDEX ' + @pk_blockers + ' ON orbit_ft;');
END
```

---

**Batch 11 — View: vw_projects_latest**

```sql
IF OBJECT_ID('dbo.vw_projects_latest', 'V') IS NOT NULL DROP VIEW dbo.vw_projects_latest;
```

Then run:

```sql
CREATE VIEW dbo.vw_projects_latest AS
SELECT
    p.id            AS project_id,
    p.name          AS project_name,
    p.customer_name,
    e.full_name     AS owner_name,
    e.email         AS owner_email,
    e.id            AS owner_id,
    sr.rag_status,
    sr.pct_hours_consumed,
    sr.total_hours_budget,
    sr.hours_consumed,
    sr.submission_at AS last_updated,
    sr.needs_review,
    sr.id           AS latest_report_id
FROM dbo.projects p
JOIN dbo.employees e ON p.owner_id = e.id
OUTER APPLY (
    SELECT TOP 1 *
    FROM dbo.status_reports
    WHERE project_id = p.id
    ORDER BY submission_at DESC
) sr
WHERE p.is_active = 1;
```

---

**Batch 12 — View: vw_team_rag_summary**

```sql
IF OBJECT_ID('dbo.vw_team_rag_summary', 'V') IS NOT NULL DROP VIEW dbo.vw_team_rag_summary;
```

Then run:

```sql
CREATE VIEW dbo.vw_team_rag_summary AS
SELECT
    mgr.id          AS manager_id,
    mgr.full_name   AS manager_name,
    emp.id          AS employee_id,
    emp.full_name   AS employee_name,
    emp.email       AS employee_email,
    COUNT(CASE WHEN v.rag_status = 'GREEN' THEN 1 END) AS green_count,
    COUNT(CASE WHEN v.rag_status = 'AMBER' THEN 1 END) AS amber_count,
    COUNT(CASE WHEN v.rag_status = 'RED'   THEN 1 END) AS red_count,
    COUNT(v.project_id)                                 AS total_active_projects
FROM dbo.employees mgr
JOIN dbo.employees emp ON emp.manager_id = mgr.id
LEFT JOIN dbo.vw_projects_latest v ON v.owner_id = emp.id
WHERE mgr.is_supervisor = 1 AND emp.is_active = 1
GROUP BY mgr.id, mgr.full_name, emp.id, emp.full_name, emp.email;
```

---

**Batch 13 — Seed supervisor**

```sql
IF NOT EXISTS (SELECT 1 FROM dbo.employees WHERE email = 'will@presidiorocks.com')
    INSERT INTO dbo.employees (email, display_name, domain, is_supervisor)
    VALUES ('will@presidiorocks.com', 'Will Mason', 'presidiorocks.com', 1);
```

---

### 4. Verify

Run this query to confirm all objects were created:

```sql
SELECT type_desc, name FROM sys.objects
WHERE schema_id = SCHEMA_ID('dbo')
  AND type IN ('U', 'V')
ORDER BY type_desc, name;
```

You should see:

| type_desc | name |
|---|---|
| USER_TABLE | blockers |
| USER_TABLE | employees |
| USER_TABLE | milestones |
| USER_TABLE | projects |
| USER_TABLE | status_reports |
| USER_TABLE | supervisor_notes |
| VIEW | vw_projects_latest |
| VIEW | vw_team_rag_summary |

And confirm the supervisor seed:

```sql
SELECT id, email, display_name, is_supervisor FROM dbo.employees;
```

### 5. Done

The schema is deployed. No need to close anything — the Query Editor session will expire on its own. If you added a client IP firewall rule, you can remove it from **sql-avsnetmon → Networking → Firewall rules** to keep the server locked down.
