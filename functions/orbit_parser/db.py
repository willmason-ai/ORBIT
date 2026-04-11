"""
SQL persistence for the parser pipeline.

All writes happen inside a single transaction per submission so a parse
failure leaves no orphan rows.
"""
from __future__ import annotations

import json
import logging
import os
from contextlib import contextmanager
from datetime import date, datetime
from typing import Any, Iterator

import pyodbc

from .project_matcher import find_or_create_project

log = logging.getLogger(__name__)

PROJECT_MATCH_THRESHOLD = float(os.environ.get("PROJECT_MATCH_THRESHOLD", "0.85"))


@contextmanager
def get_connection() -> Iterator[pyodbc.Connection]:
    conn_str = os.environ["SQL_CONNECTION_STRING"]
    conn = pyodbc.connect(conn_str, autocommit=False)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _upsert_employee(
    cursor,
    email: str,
    display_name: str | None,
) -> int:
    domain = email.split("@", 1)[1] if "@" in email else None
    cursor.execute(
        """
        MERGE dbo.employees AS tgt
        USING (SELECT ? AS email) AS src
           ON tgt.email = src.email
        WHEN MATCHED THEN
            UPDATE SET
                display_name = COALESCE(?, tgt.display_name),
                domain       = COALESCE(tgt.domain, ?),
                last_seen    = SYSUTCDATETIME(),
                report_count = tgt.report_count + 1
        WHEN NOT MATCHED THEN
            INSERT (email, display_name, domain, report_count, first_seen, last_seen)
            VALUES (src.email, ?, ?, 1, SYSUTCDATETIME(), SYSUTCDATETIME())
        OUTPUT INSERTED.id;
        """,
        email, display_name, domain, display_name, domain,
    )
    row = cursor.fetchone()
    return row[0]


def _parse_date(value: Any) -> date | None:
    if not value:
        return None
    if isinstance(value, date):
        return value
    try:
        return datetime.fromisoformat(str(value)).date()
    except ValueError:
        return None


def upsert_status_report(
    conn: pyodbc.Connection,
    sender_email: str,
    sender_display_name: str | None,
    submission_at: datetime,
    email_body: str,
    blob_path: str,
    blob_url: str,
    agent_result: dict[str, Any],
) -> int:
    """
    Write employee upsert + project match + status_report + milestones + blockers.
    Returns the new status_report id.
    """
    cursor = conn.cursor()

    employee_id = _upsert_employee(cursor, sender_email, sender_display_name)

    project_name  = agent_result.get("project_name") or "(unknown project)"
    customer_name = agent_result.get("customer_name")
    project_id, was_created = find_or_create_project(
        cursor=cursor,
        extracted_name=project_name,
        customer_name=customer_name,
        employee_id=employee_id,
        confidence_threshold=PROJECT_MATCH_THRESHOLD,
    )

    period       = agent_result.get("reporting_period") or {}
    period_start = _parse_date(period.get("start"))
    period_end   = _parse_date(period.get("end"))

    cursor.execute(
        """
        INSERT INTO dbo.status_reports (
            project_id, employee_id, submission_at,
            rag_status, rag_rationale,
            total_hours_budget, hours_consumed,
            reporting_period_start, reporting_period_end,
            narrative_summary, email_body_text,
            blob_url, blob_path,
            parse_confidence, needs_review,
            raw_agent_json
        )
        OUTPUT INSERTED.id
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        project_id,
        employee_id,
        submission_at,
        agent_result.get("rag_status"),
        agent_result.get("rag_rationale"),
        agent_result.get("total_hours_budgeted"),
        agent_result.get("hours_consumed"),
        period_start,
        period_end,
        agent_result.get("narrative_summary"),
        email_body,
        blob_url,
        blob_path,
        agent_result.get("parse_confidence"),
        1 if agent_result.get("needs_review") else 0,
        agent_result.get("raw_agent_json") or json.dumps(agent_result),
    )
    report_id = cursor.fetchone()[0]

    for ms in agent_result.get("milestones") or []:
        cursor.execute(
            """
            INSERT INTO dbo.milestones (report_id, description, completed, due_date)
            VALUES (?, ?, ?, ?)
            """,
            report_id,
            ms.get("description") or "",
            1 if ms.get("completed") else 0,
            _parse_date(ms.get("due_date")),
        )

    for bl in agent_result.get("blockers") or []:
        cursor.execute(
            """
            INSERT INTO dbo.blockers (report_id, description, severity)
            VALUES (?, ?, ?)
            """,
            report_id,
            bl.get("description") or "",
            bl.get("severity"),
        )

    cursor.execute(
        "UPDATE dbo.projects SET updated_at = SYSUTCDATETIME() WHERE id = ?",
        project_id,
    )

    return report_id
