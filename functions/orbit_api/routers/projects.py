"""/api/projects routes."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import CurrentUser, current_user
from ..db import get_connection, row_to_dict, rows_to_dicts

router = APIRouter()


@router.get("")
def list_projects(
    search: str | None = Query(default=None),
    rag: str | None = Query(default=None),
    employee_id: int | None = Query(default=None),
    needs_review: bool | None = Query(default=None),
    user: CurrentUser = Depends(current_user),
) -> list[dict]:
    where = ["1=1"]
    params: list = []
    if search:
        where.append("(v.project_name LIKE ? OR v.customer_name LIKE ?)")
        params += [f"%{search}%", f"%{search}%"]
    if rag:
        where.append("v.rag_status = ?")
        params.append(rag.upper())
    if employee_id:
        where.append("v.owner_id = ?")
        params.append(employee_id)
    if needs_review is not None:
        where.append("v.needs_review = ?")
        params.append(1 if needs_review else 0)

    sql = f"""
        SELECT v.*
        FROM dbo.vw_projects_latest v
        WHERE {' AND '.join(where)}
        ORDER BY v.last_updated DESC
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql, *params)
        return rows_to_dicts(cursor)


@router.get("/{project_id}")
def get_project(project_id: int, user: CurrentUser = Depends(current_user)) -> dict:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT * FROM dbo.vw_projects_latest WHERE project_id = ?",
            project_id,
        )
        data = row_to_dict(cursor)
        if not data:
            raise HTTPException(404, "project not found")
        return data


@router.get("/{project_id}/history")
def project_history(project_id: int, user: CurrentUser = Depends(current_user)) -> list[dict]:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT id, submission_at, rag_status, pct_hours_consumed,
                   total_hours_budget, hours_consumed, parse_confidence, needs_review
            FROM dbo.status_reports
            WHERE project_id = ?
            ORDER BY submission_at DESC
            """,
            project_id,
        )
        return rows_to_dicts(cursor)
