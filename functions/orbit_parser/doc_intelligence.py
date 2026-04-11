"""
Azure AI Document Intelligence fallback.

python-pptx handles most decks, but image-only or scan-based slides
produce almost no text. When a slide has fewer than ~20 characters of
recoverable text we ship the entire PPTX to Document Intelligence's
'prebuilt-layout' model and merge the recovered lines into the shape
list as synthetic text shapes.
"""
from __future__ import annotations

import logging
import os
from typing import Any

from azure.ai.formrecognizer import DocumentAnalysisClient
from azure.core.credentials import AzureKeyCredential

log = logging.getLogger(__name__)

MIN_SLIDE_CHARS = 20


def enrich_with_document_intelligence(pptx_data: dict[str, Any], file_bytes: bytes) -> dict[str, Any]:
    endpoint = os.environ.get("DOCINT_ENDPOINT")
    key      = os.environ.get("DOCINT_KEY")
    if not endpoint or not key:
        log.info("Document Intelligence not configured; skipping fallback.")
        return pptx_data

    thin_slides = [s for s in pptx_data["slides"] if _slide_text_length(s) < MIN_SLIDE_CHARS]
    if not thin_slides:
        return pptx_data

    log.info("Running Document Intelligence fallback for %d thin slides", len(thin_slides))

    try:
        client = DocumentAnalysisClient(endpoint=endpoint, credential=AzureKeyCredential(key))
        poller = client.begin_analyze_document("prebuilt-layout", document=file_bytes)
        result = poller.result()
    except Exception:
        log.exception("Document Intelligence call failed; proceeding without enrichment.")
        return pptx_data

    # Pages in layout result map 1:1 to slides.
    for page in result.pages:
        slide_num = page.page_number
        if slide_num <= 0 or slide_num > len(pptx_data["slides"]):
            continue
        target = pptx_data["slides"][slide_num - 1]
        if _slide_text_length(target) >= MIN_SLIDE_CHARS:
            continue
        lines = [line.content for line in page.lines if line.content and line.content.strip()]
        if not lines:
            continue
        target["shapes"].append({
            "shape_name": "docint_fallback",
            "text": "\n".join(lines),
            "fill_rgb": None,
            "rag_hint": None,
        })

    return pptx_data


def _slide_text_length(slide: dict[str, Any]) -> int:
    total = len(slide.get("slide_title") or "")
    for shape in slide.get("shapes", []):
        total += len(shape.get("text") or "")
    for table in slide.get("tables", []):
        for row in table.get("rows", []):
            for cell in row:
                total += len(cell or "")
    return total
