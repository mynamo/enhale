"""Blood work contract — structured lab results extracted from an uploaded
report (PDF/PNG/JPEG) via Claude's document/vision input."""

from __future__ import annotations

from datetime import date, datetime
from typing import Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class BloodMarker(BaseModel):
    """One lab result line."""

    name: str                                   # e.g. "Hemoglobin A1c"
    value: str                                  # raw value as printed, e.g. "5.4", "Negative"
    value_num: Optional[float] = None           # numeric parse of value, when numeric
    unit: Optional[str] = None                  # e.g. "%", "mg/dL"
    reference_range: Optional[str] = None        # e.g. "4.0-5.6"
    flag: Optional[str] = None                  # "high" | "low" | "normal" | None


class BloodWorkPanel(BaseModel):
    """A single uploaded report and everything extracted from it."""

    id: UUID = Field(default_factory=uuid4)
    collected_on: Optional[date] = None         # collection date, if the report shows one
    source_filename: str
    markers: list[BloodMarker]
    note: Optional[str] = None                  # any caveat from extraction
    created_at: Optional[datetime] = None       # when uploaded
