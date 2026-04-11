"""/api/employees routes."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ..auth import CurrentUser, current_user, require_supervisor
from ..db import get_connection, row_to_dict, rows_to_dicts

router = APIRouter()


@router.get("")
def list_employees(user: CurrentUser = Depends(require_supervisor)) -> list[dict]:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT id, email, display_name, full_name, domain, manager_id,
                   is_supervisor, report_count, last_seen
            FROM dbo.employees
            WHERE is_active = 1
            ORDER BY full_name
            """
        )
        return rows_to_dicts(cursor)


@router.get("/{employee_id}")
def get_employee(employee_id: int, user: CurrentUser = Depends(require_supervisor)) -> dict:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT id, email, display_name, full_name, domain, manager_id,
                   is_supervisor, report_count, first_seen, last_seen, notes
            FROM dbo.employees
            WHERE id = ?
            """,
            employee_id,
        )
        data = row_to_dict(cursor)
        if not data:
            raise HTTPException(404, "employee not found")
        return data


@router.get("/{employee_id}/projects")
def employee_projects(
    employee_id: int,
    user: CurrentUser = Depends(require_supervisor),
) -> list[dict]:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT * FROM dbo.vw_projects_latest
            WHERE owner_id = ?
            ORDER BY last_updated DESC
            """,
            employee_id,
        )
        return rows_to_dicts(cursor)
