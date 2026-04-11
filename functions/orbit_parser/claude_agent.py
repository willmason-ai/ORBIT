"""
Claude agent — extracts a validated ProjectStatusReport JSON from PPTX data.

Model: claude-sonnet-4-6. The agent is a single extraction call; no tools
and no multi-turn loop are needed. Output is a plain JSON object matching
the schema in the system prompt.
"""
from __future__ import annotations

import json
import logging
import os
import re
from typing import Any

import anthropic

log = logging.getLogger(__name__)

_client: anthropic.Anthropic | None = None


def _get_client() -> anthropic.Anthropic:
    global _client
    if _client is None:
        _client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    return _client


MODEL_ID = "claude-sonnet-4-6"

SYSTEM_PROMPT = """
You are ORBIT's project status extraction agent.
You receive raw text and color metadata extracted from a PowerPoint status report
submitted by an engineer. Your job is to return a single JSON object conforming
exactly to the schema below. Do not add markdown. Do not add commentary.
Return ONLY the JSON object.

OUTPUT SCHEMA:
{
  "project_name": "string - exact name of the project",
  "customer_name": "string or null",
  "total_hours_budgeted": number_or_null,
  "hours_consumed": number_or_null,
  "rag_status": "RED" or "AMBER" or "GREEN" or null,
  "rag_rationale": "string - why this status, in 1-2 sentences, or null",
  "reporting_period": {
    "start": "YYYY-MM-DD or null",
    "end": "YYYY-MM-DD or null"
  },
  "milestones": [
    { "description": "string", "completed": true_or_false, "due_date": "YYYY-MM-DD or null" }
  ],
  "blockers": [
    { "description": "string", "severity": "HIGH" or "MEDIUM" or "LOW" or null }
  ],
  "narrative_summary": "string - 2-3 sentence plain English summary of overall status, or null",
  "parse_confidence": 0.0_to_1.0
}

EXTRACTION RULES:
1. RAG STATUS - check in this order:
   a. Color hints in the slide data: rag_hint = RED -> "RED", AMBER -> "AMBER", GREEN -> "GREEN"
   b. Text labels: "ON TRACK" or "GREEN" -> GREEN; "AT RISK" or "AMBER" or "WATCH" -> AMBER;
      "CRITICAL" or "OFF TRACK" or "RED" or "BEHIND" -> RED
   c. If ambiguous, use the most prominent colored shape on what appears to be a status slide.

2. HOURS - look for any of these patterns:
   "X of Y hours", "Budget: Y / Consumed: X", "X hrs consumed", "X/Y hrs",
   percentages like "65% complete" combined with a total budget elsewhere.

3. MILESTONES - look for slides/sections titled "Milestones", "Accomplishments",
   "Progress", "Schedule". Completed items often have checkmarks, strikethrough,
   or explicit "Complete"/"Done" labels. Upcoming items may have future dates,
   "In Progress", or "Planned" labels.

4. BLOCKERS - look for slides/sections titled "Issues", "Risks", "Problems",
   "Impediments", "Blockers", "Challenges". Rate severity:
   HIGH = blocking delivery or requiring immediate escalation
   MEDIUM = impacting schedule but workaround exists
   LOW = minor, informational only

5. parse_confidence - your honest estimate (0.0 to 1.0) of how confident you are
   in the extraction. Set below 0.70 if:
   - project name is ambiguous or missing
   - no clear RAG signal found
   - hours data is absent
   - slide content appears to be a generic or non-status deck

Return null for any field you cannot extract with reasonable confidence.
Never fabricate data.
""".strip()


def extract_project_status(
    pptx_data: dict[str, Any],
    email_body: str,
    sender_email: str,
) -> dict[str, Any]:
    """
    Call Claude to extract structured project status from PPTX extraction output.
    Returns the parsed JSON dict with an extra `raw_agent_json` key holding the
    original model output string for audit.
    """
    user_content = (
        f"SENDER: {sender_email}\n\n"
        f"EMAIL BODY:\n{email_body or '(no email body text)'}\n\n"
        f"POWERPOINT EXTRACTION ({pptx_data['slide_count']} slides):\n"
        f"{json.dumps(pptx_data['slides'], indent=2, default=str)}\n"
    )

    client = _get_client()
    response = client.messages.create(
        model=MODEL_ID,
        max_tokens=2000,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_content}],
    )

    raw_text = response.content[0].text.strip()

    # Strip any accidental markdown fences
    raw_text = re.sub(r"^```json\s*", "", raw_text)
    raw_text = re.sub(r"^```\s*", "", raw_text)
    raw_text = re.sub(r"\s*```$", "", raw_text)

    try:
        result: dict[str, Any] = json.loads(raw_text)
    except json.JSONDecodeError:
        log.exception("Claude returned invalid JSON; raw=%s", raw_text[:2000])
        return {
            "project_name": None,
            "customer_name": None,
            "total_hours_budgeted": None,
            "hours_consumed": None,
            "rag_status": None,
            "rag_rationale": None,
            "reporting_period": {"start": None, "end": None},
            "milestones": [],
            "blockers": [],
            "narrative_summary": None,
            "parse_confidence": 0.0,
            "raw_agent_json": raw_text,
        }

    result["raw_agent_json"] = raw_text
    return result
