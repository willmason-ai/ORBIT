"""
ORBIT FastAPI application — served via AsgiFunctionApp.
"""
from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .routers import dashboard, employees, projects, reports, search

log = logging.getLogger(__name__)

app = FastAPI(
    title="ORBIT API",
    version="1.0.0",
    description="Operations Reporting & Brief Intelligence Tracker",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tightened by App Service auth / Front Door in practice
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health", tags=["meta"])
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(projects.router,  prefix="/api/projects",  tags=["projects"])
app.include_router(employees.router, prefix="/api/employees", tags=["employees"])
app.include_router(reports.router,   prefix="/api/reports",   tags=["reports"])
app.include_router(dashboard.router, prefix="/api/dashboard", tags=["dashboard"])
app.include_router(search.router,    prefix="/api/search",    tags=["search"])
