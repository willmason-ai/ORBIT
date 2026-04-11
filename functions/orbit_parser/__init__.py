"""
orbit_parser — blob-triggered PPTX ingestion pipeline.

Blob path convention written by the Logic App ingestor:
    orbit-pptx-raw/{sender_email}/{yyyyMMdd_HHmmss}__{original_filename}.pptx

The JSON sidecar (same path, .json extension) carries email metadata that
python-pptx cannot recover from the deck itself (sender, subject, body,
received timestamp). When the sidecar is missing we fall back to parsing
the blob name.
"""
from __future__ import annotations

import json
import logging
import os
import re
from datetime import datetime, timezone
from typing import Any
from urllib.parse import unquote

from azure.identity import DefaultAzureCredential
from azure.storage.blob import (
    BlobClient,
    BlobSasPermissions,
    BlobServiceClient,
    generate_blob_sas,
)

from .claude_agent import extract_project_status
from .db import get_connection, upsert_status_report
from .doc_intelligence import enrich_with_document_intelligence
from .pptx_extractor import extract_pptx

log = logging.getLogger(__name__)

STORAGE_ACCOUNT = os.environ.get("STORAGE_ACCOUNT_NAME", "")
CONTAINER       = os.environ.get("BLOB_CONTAINER_NAME", "orbit-pptx-raw")
CONFIDENCE_MIN  = float(os.environ.get("PARSE_CONFIDENCE_THRESHOLD", "0.70"))


def handle_blob(blob_name: str, blob_bytes: bytes) -> None:
    """Pipeline entry. Called by the Functions blob trigger."""
    log.info("ORBIT parser starting for %s (%d bytes)", blob_name, len(blob_bytes))

    if not blob_name.lower().endswith(".pptx"):
        log.info("Skipping non-pptx blob: %s", blob_name)
        return

    # Step 0: email metadata (from sidecar or filename fallback)
    meta = _load_email_metadata(blob_name)

    # Step 1: python-pptx structured extraction
    pptx_data = extract_pptx(blob_bytes)

    # Step 2: Document Intelligence fallback for image-heavy slides
    pptx_data = enrich_with_document_intelligence(pptx_data, blob_bytes)

    # Step 3: Claude agent — produce validated JSON
    agent_result = extract_project_status(
        pptx_data=pptx_data,
        email_body=meta.get("email_body", ""),
        sender_email=meta["sender_email"],
    )
    agent_result["needs_review"] = agent_result.get("parse_confidence", 1.0) < CONFIDENCE_MIN

    # Step 4: persist
    blob_url = _generate_blob_sas_url(blob_name)
    with get_connection() as conn:
        report_id = upsert_status_report(
            conn,
            sender_email=meta["sender_email"],
            sender_display_name=meta.get("sender_display_name"),
            submission_at=meta["submission_at"],
            email_body=meta.get("email_body", ""),
            blob_path=_strip_container(blob_name),
            blob_url=blob_url,
            agent_result=agent_result,
        )
    log.info("ORBIT parser finished: report_id=%s needs_review=%s",
             report_id, agent_result["needs_review"])


def _load_email_metadata(blob_name: str) -> dict[str, Any]:
    """Load the .json sidecar the ingestor Logic App writes next to the .pptx."""
    try:
        cred = DefaultAzureCredential()
        bsc = BlobServiceClient(
            account_url=f"https://{STORAGE_ACCOUNT}.blob.core.windows.net",
            credential=cred,
        )
        sidecar_path = _strip_container(blob_name).rsplit(".", 1)[0] + ".json"
        bc = bsc.get_blob_client(container=CONTAINER, blob=sidecar_path)
        raw = bc.download_blob().readall()
        data = json.loads(raw)
        return {
            "sender_email":        data["sender_email"].lower(),
            "sender_display_name": data.get("sender_display_name"),
            "email_body":          data.get("email_body", ""),
            "submission_at":       _parse_iso(data.get("received_at")) or datetime.now(timezone.utc),
        }
    except Exception as exc:
        log.warning("No sidecar for %s (%s); falling back to filename parse.", blob_name, exc)
        return _parse_blob_name_fallback(blob_name)


def _parse_blob_name_fallback(blob_name: str) -> dict[str, Any]:
    stripped = _strip_container(blob_name)
    parts = stripped.split("/", 1)
    sender = unquote(parts[0]) if len(parts) == 2 else "unknown@unknown"
    return {
        "sender_email":        sender.lower(),
        "sender_display_name": None,
        "email_body":          "",
        "submission_at":       datetime.now(timezone.utc),
    }


def _strip_container(blob_name: str) -> str:
    # Blob trigger delivers "name" = path inside the container already,
    # but some Logic App configurations send the full container-qualified
    # path. Normalize both.
    if blob_name.startswith(f"{CONTAINER}/"):
        return blob_name[len(CONTAINER) + 1 :]
    return blob_name


def _parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _generate_blob_sas_url(blob_name: str) -> str:
    """Return a URL with no SAS; actual SAS generation is done on-demand by the API."""
    path = _strip_container(blob_name)
    return f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{path}"
