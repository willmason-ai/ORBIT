"""
Read-side database helpers for the API.
"""
from __future__ import annotations

import os
from contextlib import contextmanager
from typing import Any, Iterator

import pyodbc


@contextmanager
def get_connection() -> Iterator[pyodbc.Connection]:
    conn = pyodbc.connect(os.environ["SQL_CONNECTION_STRING"], autocommit=True)
    try:
        yield conn
    finally:
        conn.close()


def rows_to_dicts(cursor: pyodbc.Cursor) -> list[dict[str, Any]]:
    columns = [col[0] for col in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def row_to_dict(cursor: pyodbc.Cursor) -> dict[str, Any] | None:
    columns = [col[0] for col in cursor.description]
    row = cursor.fetchone()
    return dict(zip(columns, row)) if row else None
