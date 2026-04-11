"""
Pydantic request/response models for the ORBIT API.
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field

RagStatus = Literal["RED", "AMBER", "GREEN"]
Severity = Literal["HIGH", "MEDIUM", "LOW"]


class ProjectSummary(BaseModel):
    project_id: int
    project_name: str
    customer_name: str | None = None
    owner_name: str | None = None
    owner_email: str | None = None
    owner_id: int | None = None
    rag_status: RagStatus | None = None
    pct_hours_consumed: float | None = None
    total_hours_budget: float | None = None
    hours_consumed: float | None = None
    last_updated: datetime | None = None
    needs_review: bool = False
    latest_report_id: int | None = None


class Milestone(BaseModel):
    id: int
    description: str
    completed: bool
    due_date: date | None = None


class Blocker(BaseModel):
    id: int
    description: str
    severity: Severity | None = None
    is_resolved: bool = False


class SupervisorNote(BaseModel):
    id: int
    note_text: str
    created_at: datetime
    supervisor_name: str | None = None


class ReportDetail(BaseModel):
    id: int
    project_id: int
    project_name: str
    employee_id: int
    employee_name: str | None = None
    employee_email: str
    submission_at: datetime
    rag_status: RagStatus | None = None
    rag_rationale: str | None = None
    total_hours_budget: float | None = None
    hours_consumed: float | None = None
    pct_hours_consumed: float | None = None
    reporting_period_start: date | None = None
    reporting_period_end: date | None = None
    narrative_summary: str | None = None
    email_body_text: str | None = None
    parse_confidence: float | None = None
    needs_review: bool = False
    blob_url: str | None = None
    milestones: list[Milestone] = Field(default_factory=list)
    blockers: list[Blocker] = Field(default_factory=list)
    notes: list[SupervisorNote] = Field(default_factory=list)


class Employee(BaseModel):
    id: int
    email: str
    display_name: str | None = None
    domain: str | None = None
    manager_id: int | None = None
    is_supervisor: bool = False
    report_count: int = 0
    last_seen: datetime | None = None


class TeamRow(BaseModel):
    employee_id: int
    employee_name: str
    employee_email: str
    green_count: int
    amber_count: int
    red_count: int
    total_active_projects: int


class NoteCreate(BaseModel):
    note_text: str


class CorrectionPayload(BaseModel):
    project_name: str | None = None
    customer_name: str | None = None
    rag_status: RagStatus | None = None
    rag_rationale: str | None = None
    total_hours_budget: float | None = None
    hours_consumed: float | None = None
    narrative_summary: str | None = None
