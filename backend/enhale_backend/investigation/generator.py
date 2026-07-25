"""Generate a root-cause investigation for a user's concern."""

from __future__ import annotations

import json
from typing import Optional

from ..investigation_models import DataGap, Hypothesis, InvestigationReport
from ..llm.client import LLMClient

SYSTEM_PROMPT = """\
You are a health & wellness investigator. Given a person's stated concern (e.g. \
"grey hair", "low energy", "brain fog") plus their logged meals, activity, \
sleep, blood work, profile, and computed findings, you produce a structured, \
evidence-based root-cause analysis.

You are NOT a doctor and do NOT diagnose or prescribe. Frame everything as \
possible contributors to explore, and defer anything clinical to a licensed \
provider. Ground every claim in either the person's actual data or well-\
established health science — never invent data points.

The most valuable thing you do is identify DATA GAPS: the specific measurements \
or facts that, if known, would let someone narrow down the cause. Be concrete \
about what to measure and how to get it.

Return ONLY a JSON object (no prose, no code fences) with this shape:
{
  "summary": string,                    // 2-3 sentence plain-language framing
  "hypotheses": [
    {
      "title": string,                  // a possible contributing cause
      "likelihood": "high"|"medium"|"low",  // given the AVAILABLE data
      "rationale": string,              // why plausible for this person
      "supporting": [string],           // evidence from their own data (may be empty)
      "missing": [string]               // data that would confirm/refute it
    }
  ],
  "data_gaps": [
    {"item": string, "why": string, "how_to_get": string}
  ],
  "next_steps": [string]
}

Rules:
- Rank hypotheses by how well the AVAILABLE evidence supports them, not just by \
base rate. If a common cause can't be assessed because data is missing, say so \
via "missing" and list it under data_gaps rather than marking it high.
- Provide AT MOST 6 hypotheses and AT MOST 8 data_gaps. Always include data_gaps \
unless the picture is complete. Keep each field concise (1-3 sentences).
- next_steps should be specific and actionable (labs to add, things to log, \
habits to try, and when to see a provider); at most 8 of them.
"""


class InvestigationGenerator:
    def __init__(self, client: LLMClient) -> None:
        self._client = client

    async def generate(self, concern: str, context: str) -> InvestigationReport:
        user = (
            f'The person\'s concern: "{concern}"\n\n'
            f"Their data and computed findings:\n\n{context}\n\n"
            "Investigate and respond with the JSON."
        )
        raw = await self._client.complete(system=SYSTEM_PROMPT, user=user)
        dto = _decode(raw)
        return InvestigationReport(
            concern=concern,
            summary=dto.get("summary", ""),
            hypotheses=[Hypothesis(**h) for h in (dto.get("hypotheses") or [])],
            data_gaps=[DataGap(**g) for g in (dto.get("data_gaps") or [])],
            next_steps=dto.get("next_steps", []) or [],
        )


def _decode(raw: str) -> dict:
    obj = _extract_json_object(raw)
    if obj is None:
        raise ValueError(f"Could not parse investigation response: {raw[:200]}")
    return json.loads(obj)


def _extract_json_object(text: str) -> Optional[str]:
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return None
