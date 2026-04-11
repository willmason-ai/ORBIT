"""
Fuzzy project matching. If a close match to an existing active project
owned by this employee exists, link to it. Otherwise create a new row.
"""
from __future__ import annotations

import difflib
import logging

log = logging.getLogger(__name__)


def find_or_create_project(
    cursor,
    extracted_name: str,
    customer_name: str | None,
    employee_id: int,
    confidence_threshold: float = 0.85,
) -> tuple[int, bool]:
    """
    Returns (project_id, was_created).
    """
    normalized = (extracted_name or "").lower().strip()
    if not normalized:
        raise ValueError("extracted_name is required")

    cursor.execute(
        """
        SELECT id, name_normalized FROM dbo.projects
        WHERE owner_id = ? AND is_active = 1
        """,
        employee_id,
    )
    rows = cursor.fetchall()

    if rows:
        names = [row[1] for row in rows if row[1]]
        matches = difflib.get_close_matches(
            normalized, names, n=1, cutoff=confidence_threshold
        )
        if matches:
            matched = next(r for r in rows if r[1] == matches[0])
            log.info("Project match: '%s' -> id=%s '%s'", extracted_name, matched[0], matched[1])
            return matched[0], False

    cursor.execute(
        """
        INSERT INTO dbo.projects (name, name_normalized, customer_name, owner_id)
        OUTPUT INSERTED.id
        VALUES (?, ?, ?, ?)
        """,
        extracted_name, normalized, customer_name, employee_id,
    )
    new_id = cursor.fetchone()[0]
    log.info("Project created: id=%s '%s'", new_id, extracted_name)
    return new_id, True
