-- ============================================================
-- ORBIT Database Schema
-- Azure SQL Serverless GP_S_Gen5_1
-- ============================================================
-- Run as the orbitdb database owner. Safe to re-run: each CREATE
-- is guarded by an existence check so Phase-1 redeploys don't fail.
-- ============================================================

-- ------------------------------------------------------------
-- EMPLOYEES
-- Unified reporter + supervisor entity. Engineers are silently
-- auto-created on first inbound email (from the From: header).
-- Supervisors are seeded manually or via the dashboard's first
-- Entra ID sign-in handler. manager_id is a self-FK that drives
-- the supervisor rollup view.
-- ------------------------------------------------------------
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
GO

-- ------------------------------------------------------------
-- PROJECTS
-- Auto-created on first mention; supervisor can edit name,
-- customer, or deactivate. Fuzzy matching uses name_normalized.
-- ------------------------------------------------------------
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
GO

-- ------------------------------------------------------------
-- STATUS REPORTS
-- One row per inbound email submission. raw_agent_json preserves
-- the full Claude response for audit / re-parse.
-- ------------------------------------------------------------
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
GO

-- ------------------------------------------------------------
-- MILESTONES
-- ------------------------------------------------------------
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
GO

-- ------------------------------------------------------------
-- BLOCKERS
-- ------------------------------------------------------------
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
GO

-- ------------------------------------------------------------
-- SUPERVISOR NOTES
-- ------------------------------------------------------------
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
GO

-- ============================================================
-- FULL-TEXT SEARCH
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = 'orbit_ft')
    CREATE FULLTEXT CATALOG orbit_ft AS DEFAULT;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.fulltext_indexes
    WHERE object_id = OBJECT_ID('dbo.projects')
)
BEGIN
    DECLARE @pk_projects NVARCHAR(256) =
        (SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.projects') AND is_primary_key = 1);
    EXEC('CREATE FULLTEXT INDEX ON dbo.projects(name, customer_name) KEY INDEX ' + @pk_projects + ' ON orbit_ft;');
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.fulltext_indexes
    WHERE object_id = OBJECT_ID('dbo.status_reports')
)
BEGIN
    DECLARE @pk_reports NVARCHAR(256) =
        (SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.status_reports') AND is_primary_key = 1);
    EXEC('CREATE FULLTEXT INDEX ON dbo.status_reports(narrative_summary, rag_rationale, email_body_text) KEY INDEX ' + @pk_reports + ' ON orbit_ft;');
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.fulltext_indexes
    WHERE object_id = OBJECT_ID('dbo.blockers')
)
BEGIN
    DECLARE @pk_blockers NVARCHAR(256) =
        (SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.blockers') AND is_primary_key = 1);
    EXEC('CREATE FULLTEXT INDEX ON dbo.blockers(description) KEY INDEX ' + @pk_blockers + ' ON orbit_ft;');
END
GO

-- ============================================================
-- VIEWS
-- ============================================================

IF OBJECT_ID('dbo.vw_projects_latest', 'V') IS NOT NULL DROP VIEW dbo.vw_projects_latest;
GO
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
GO

IF OBJECT_ID('dbo.vw_team_rag_summary', 'V') IS NOT NULL DROP VIEW dbo.vw_team_rag_summary;
GO
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
GO
