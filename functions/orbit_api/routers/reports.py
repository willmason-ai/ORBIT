"""/api/reports routes."""
from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobSasPermissions, BlobServiceClient, generate_blob_sas
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import RedirectResponse

from ..auth import CurrentUser, current_user, require_supervisor
from ..db import get_connection, row_to_dict, rows_to_dicts
from ..models import CorrectionPayload, NoteCreate

router = APIRouter()

STORAGE_ACCOUNT = os.environ.get("STORAGE_ACCOUNT_NAME", "")
CONTAINER       = os.environ.get("BLOB_CONTAINER_NAME", "orbit-pptx-raw")


@router.get("/{report_id}")
def get_report(report_id: int, user: CurrentUser = Depends(current_user)) -> dict:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT sr.id, sr.project_id, p.name AS project_name,
                   sr.employee_id, e.full_name AS employee_name, e.email AS employee_email,
                   sr.submission_at, sr.rag_status, sr.rag_rationale,
                   sr.total_hours_budget, sr.hours_consumed, sr.pct_hours_consumed,
                   sr.reporting_period_start, sr.reporting_period_end,
                   sr.narrative_summary, sr.email_body_text,
                   sr.parse_confidence, sr.needs_review, sr.blob_url
            FROM dbo.status_reports sr
            JOIN dbo.projects p  ON p.id = sr.project_id
            JOIN dbo.employees e ON e.id = sr.employee_id
            WHERE sr.id = ?
            """,
            report_id,
        )
        detail = row_to_dict(cursor)
        if not detail:
            raise HTTPException(404, "report not found")

        # Engineers may only see their own reports unless they are supervisors.
        if not user.is_supervisor and detail["employee_email"].lower() != user.email.lower():
            raise HTTPException(403, "forbidden")

        cursor.execute(
            "SELECT id, description, completed, due_date FROM dbo.milestones WHERE report_id = ?",
            report_id,
        )
        detail["milestones"] = rows_to_dicts(cursor)

        cursor.execute(
            "SELECT id, description, severity, is_resolved FROM dbo.blockers WHERE report_id = ?",
            report_id,
        )
        detail["blockers"] = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT n.id, n.note_text, n.created_at, e.full_name AS supervisor_name
            FROM dbo.supervisor_notes n
            LEFT JOIN dbo.employees e ON e.id = n.supervisor_id
            WHERE n.report_id = ?
            ORDER BY n.created_at DESC
            """,
            report_id,
        )
        detail["notes"] = rows_to_dicts(cursor)
        return detail


@router.get("/{report_id}/pptx")
def download_pptx(report_id: int, user: CurrentUser = Depends(current_user)) -> RedirectResponse:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT sr.blob_path, e.email
            FROM dbo.status_reports sr
            JOIN dbo.employees e ON e.id = sr.employee_id
            WHERE sr.id = ?
            """,
            report_id,
        )
        row = cursor.fetchone()
        if not row:
            raise HTTPException(404, "report not found")
        blob_path, owner_email = row
        if not user.is_supervisor and owner_email.lower() != user.email.lower():
            raise HTTPException(403, "forbidden")

    if not blob_path:
        raise HTTPException(404, "no blob on record")

    sas_url = _user_delegation_sas(blob_path)
    return RedirectResponse(url=sas_url, status_code=302)


def _user_delegation_sas(blob_path: str) -> str:
    cred = DefaultAzureCredential()
    bsc = BlobServiceClient(
        account_url=f"https://{STORAGE_ACCOUNT}.blob.core.windows.net",
        credential=cred,
    )
    start  = datetime.now(timezone.utc) - timedelta(minutes=5)
    expiry = datetime.now(timezone.utc) + timedelta(minutes=30)
    user_delegation_key = bsc.get_user_delegation_key(start, expiry)
    sas = generate_blob_sas(
        account_name=STORAGE_ACCOUNT,
        container_name=CONTAINER,
        blob_name=blob_path,
        user_delegation_key=user_delegation_key,
        permission=BlobSasPermissions(read=True),
        expiry=expiry,
        start=start,
    )
    return f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{blob_path}?{sas}"


@router.post("/{report_id}/notes")
def add_note(
    report_id: int,
    payload: NoteCreate,
    user: CurrentUser = Depends(require_supervisor),
) -> dict:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT id FROM dbo.employees WHERE email = ?",
            user.email,
        )
        row = cursor.fetchone()
        if not row:
            cursor.execute(
                """
                INSERT INTO dbo.employees (email, display_name, domain, is_supervisor)
                OUTPUT INSERTED.id
                VALUES (?, ?, ?, 1)
                """,
                user.email, user.name, user.email.split("@", 1)[-1],
            )
            row = cursor.fetchone()
        supervisor_id = row[0]

        cursor.execute(
            """
            INSERT INTO dbo.supervisor_notes (report_id, supervisor_id, note_text)
            OUTPUT INSERTED.id
            VALUES (?, ?, ?)
            """,
            report_id, supervisor_id, payload.note_text,
        )
        new_id = cursor.fetchone()[0]
    return {"id": new_id}


@router.post("/{report_id}/confirm")
def confirm_extraction(
    report_id: int,
    user: CurrentUser = Depends(require_supervisor),
) -> dict:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE dbo.status_reports SET needs_review = 0 WHERE id = ?",
            report_id,
        )
    return {"id": report_id, "needs_review": False}


@router.post("/{report_id}/correct")
def correct_extraction(
    report_id: int,
    payload: CorrectionPayload,
    user: CurrentUser = Depends(require_supervisor),
) -> dict:
    updates: list[str] = []
    params: list = []
    for field in (
        "rag_status", "rag_rationale",
        "total_hours_budget", "hours_consumed",
        "narrative_summary",
    ):
        value = getattr(payload, field)
        if value is not None:
            updates.append(f"{field} = ?")
            params.append(value)

    with get_connection() as conn:
        cursor = conn.cursor()
        if updates:
            updates.append("needs_review = 0")
            params.append(report_id)
            cursor.execute(
                f"UPDATE dbo.status_reports SET {', '.join(updates)} WHERE id = ?",
                *params,
            )

        if payload.project_name or payload.customer_name:
            cursor.execute(
                "SELECT project_id FROM dbo.status_reports WHERE id = ?",
                report_id,
            )
            row = cursor.fetchone()
            if row:
                project_id = row[0]
                p_updates: list[str] = []
                p_params: list = []
                if payload.project_name:
                    p_updates.append("name = ?")
                    p_updates.append("name_normalized = ?")
                    p_params.append(payload.project_name)
                    p_params.append(payload.project_name.lower().strip())
                if payload.customer_name:
                    p_updates.append("customer_name = ?")
                    p_params.append(payload.customer_name)
                p_params.append(project_id)
                cursor.execute(
                    f"UPDATE dbo.projects SET {', '.join(p_updates)}, updated_at = SYSUTCDATETIME() WHERE id = ?",
                    *p_params,
                )
    return {"id": report_id, "needs_review": False}
