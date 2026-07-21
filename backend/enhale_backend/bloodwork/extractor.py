"""Extract a structured blood-work panel from an uploaded report."""

from __future__ import annotations

import json
from typing import Optional

from ..bloodwork_models import BloodMarker, BloodWorkPanel
from ..llm.vision_client import VisionClient

SYSTEM_PROMPT = """\
You extract structured lab results from a blood work / lab report (provided as a \
PDF or image). You are precise and never invent values that aren't in the report.

Return ONLY a JSON object (no prose, no code fences) with this shape:
{
  "collected_on": "YYYY-MM-DD" | null,   // specimen collection date if shown
  "markers": [
    {
      "name": string,                    // test name, e.g. "Hemoglobin A1c"
      "value": string,                   // value exactly as printed, e.g. "5.4"
      "value_num": number | null,        // numeric value if the value is numeric
      "unit": string | null,             // e.g. "%", "mg/dL"
      "reference_range": string | null,  // e.g. "4.0-5.6"
      "flag": "high" | "low" | "normal" | null  // out-of-range status
    }
  ],
  "note": string | null                  // caveat if the document is unclear/partial
}

Rules:
- Include every distinct lab result you can read.
- Set flag from the report's own H/L markers, or by comparing value to the range.
- If the file is not a lab report, return {"markers": [], "note": "not a lab report"}.
"""

USER_PROMPT = "Extract all lab results from this report as JSON."


class BloodWorkExtractor:
    def __init__(self, client: VisionClient) -> None:
        self._client = client

    async def extract(self, filename: str, media_type: str, data_b64: str) -> BloodWorkPanel:
        raw = await self._client.extract(
            system=SYSTEM_PROMPT, user=USER_PROMPT,
            media_type=media_type, data_b64=data_b64,
        )
        dto = _decode(raw)
        markers = [BloodMarker(**m) for m in (dto.get("markers") or [])]
        return BloodWorkPanel(
            collected_on=dto.get("collected_on"),
            source_filename=filename,
            markers=markers,
            note=dto.get("note"),
        )


def _decode(raw: str) -> dict:
    obj = _extract_json_object(raw)
    if obj is None:
        raise ValueError(f"Could not parse extraction response: {raw[:200]}")
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
