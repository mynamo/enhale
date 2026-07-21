"""Insights contract — structured lifestyle recommendations synthesized from the
user's meals, health data, and blood work.

Framed as general wellness guidance, not medical diagnosis or treatment.
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class Recommendation(BaseModel):
    title: str                 # short imperative, e.g. "Cut back on late dinners"
    detail: str                # 1-3 sentences of specific, actionable advice
    category: str              # nutrition | activity | sleep | labs | general
    priority: str              # high | medium | low
    rationale: str             # the data pattern this is based on


class InsightReport(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    generated_at: Optional[datetime] = None
    summary: str                       # 1-2 sentence overview
    observations: list[str] = []       # notable patterns across the data
    recommendations: list[Recommendation]
    disclaimer: str = (
        "These are general wellness suggestions, not medical advice. "
        "Discuss any out-of-range lab results or health concerns with a licensed "
        "healthcare provider."
    )
