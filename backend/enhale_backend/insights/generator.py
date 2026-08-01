"""Generate lifestyle recommendations from the user's data via the LLM."""

from __future__ import annotations

import json
from typing import Optional

from ..insights_models import InsightReport, Recommendation
from ..llm.client import LLMClient

SYSTEM_PROMPT = """\
You are a supportive health & wellness coach. You analyze a person's recently \
logged meals, physical activity, sleep, and blood work, find meaningful \
patterns, and give specific, actionable lifestyle suggestions.

You are NOT a doctor. Give general wellness guidance about nutrition, movement, \
and sleep. Do NOT diagnose conditions or prescribe treatment or supplements/ \
dosages. For any out-of-range lab value or health concern, recommend discussing \
it with a licensed healthcare provider.

Return ONLY a JSON object (no prose, no code fences) with this shape:
{
  "summary": string,               // 1-2 sentence plain-language overview
  "observations": [string],        // notable patterns you actually see in the data
  "recommendations": [
    {
      "title": string,             // short imperative
      "detail": string,            // 1-3 sentences, specific and actionable
      "category": "nutrition"|"activity"|"sleep"|"labs"|"general",
      "priority": "high"|"medium"|"low",
      "rationale": string          // the specific data pattern this is based on
    }
  ]
}

Rules:
- Base every observation and recommendation on the actual data provided; never \
invent numbers or foods that aren't there.
- If there's little data, say so and give a couple of gentle, general suggestions.
- Provide AT MOST 5 observations and 3-6 recommendations — focus on what matters \
most, don't try to cover everything. Keep each field to 1-2 sentences.
"""


class InsightGenerator:
    def __init__(self, client: LLMClient) -> None:
        self._client = client

    async def generate(self, context: str) -> InsightReport:
        user = f"Here is the person's recent data:\n\n{context}\n\nAnalyze it and respond with the JSON."
        raw = await self._client.complete(system=SYSTEM_PROMPT, user=user)
        dto = _decode(raw)
        return InsightReport(
            summary=dto.get("summary", ""),
            observations=dto.get("observations", []) or [],
            recommendations=[Recommendation(**r) for r in (dto.get("recommendations") or [])],
        )


def _decode(raw: str) -> dict:
    obj = _extract_json_object(raw)
    if obj is None:
        raise ValueError(f"Could not parse insights response: {raw[:200]}")
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
