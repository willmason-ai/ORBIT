"""/api/search route — full-text across projects, reports, blockers."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from ..auth import CurrentUser, current_user
from ..db import get_connection, rows_to_dicts

router = APIRouter()


@router.get("")
def search(
    q: str = Query(..., min_length=2),
    user: CurrentUser = Depends(current_user),
) -> dict:
    like = f"%{q}%"
    with get_connection() as conn:
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT TOP 25 id AS project_id, name AS project_name, customer_name
            FROM dbo.projects
            WHERE is_active = 1 AND (name LIKE ? OR customer_name LIKE ?)
            ORDER BY updated_at DESC
            """,
            like, like,
        )
        projects = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT TOP 25 sr.id, sr.project_id, p.name AS project_name,
                   sr.submission_at, sr.rag_status, sr.narrative_summary
            FROM dbo.status_reports sr
            JOIN dbo.projects p ON p.id = sr.project_id
            WHERE sr.narrative_summary LIKE ? OR sr.rag_rationale LIKE ? OR sr.email_body_text LIKE ?
            ORDER BY sr.submission_at DESC
            """,
            like, like, like,
        )
        reports = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT TOP 25 b.id, b.description, b.severity, b.report_id,
                   p.name AS project_name
            FROM dbo.blockers b
            JOIN dbo.status_reports sr ON sr.id = b.report_id
            JOIN dbo.projects p ON p.id = sr.project_id
            WHERE b.description LIKE ?
            ORDER BY sr.submission_at DESC
            """,
            like,
        )
        blockers = rows_to_dicts(cursor)

    return {"projects": projects, "reports": reports, "blockers": blockers}
