"""/api/dashboard routes."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from ..auth import CurrentUser, current_user, require_supervisor
from ..db import get_connection, rows_to_dicts

router = APIRouter()


@router.get("/team")
def team_overview(user: CurrentUser = Depends(require_supervisor)) -> list[dict]:
    """One row per direct report with RAG rollup."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT employee_id, employee_name, employee_email,
                   green_count, amber_count, red_count, total_active_projects
            FROM dbo.vw_team_rag_summary
            WHERE manager_name = ? OR ? IS NULL
            ORDER BY red_count DESC, amber_count DESC, employee_name
            """,
            user.name, user.name,
        )
        rows = rows_to_dicts(cursor)
        # If the supervisor has no direct reports mapped yet, fall through
        # to "all active reporters" so the dashboard is never blank.
        if not rows:
            cursor.execute(
                """
                SELECT e.id AS employee_id, e.full_name AS employee_name, e.email AS employee_email,
                       COUNT(CASE WHEN v.rag_status = 'GREEN' THEN 1 END) AS green_count,
                       COUNT(CASE WHEN v.rag_status = 'AMBER' THEN 1 END) AS amber_count,
                       COUNT(CASE WHEN v.rag_status = 'RED'   THEN 1 END) AS red_count,
                       COUNT(v.project_id) AS total_active_projects
                FROM dbo.employees e
                LEFT JOIN dbo.vw_projects_latest v ON v.owner_id = e.id
                WHERE e.is_active = 1 AND e.is_supervisor = 0
                GROUP BY e.id, e.full_name, e.email
                ORDER BY red_count DESC, amber_count DESC, employee_name
                """
            )
            rows = rows_to_dicts(cursor)
        return rows


@router.get("/me")
def my_projects(user: CurrentUser = Depends(current_user)) -> list[dict]:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT v.*
            FROM dbo.vw_projects_latest v
            JOIN dbo.employees e ON e.id = v.owner_id
            WHERE e.email = ?
            ORDER BY v.last_updated DESC
            """,
            user.email,
        )
        return rows_to_dicts(cursor)
