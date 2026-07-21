"""Investigation ("Ask enhale") contract — the flagship differentiator.

The user asks about a concern ("why do I have grey hair?"); the system returns
ranked, evidence-based hypotheses, flags exactly what data is missing to narrow
it down, and gives concrete next steps. General wellness framing, not diagnosis.
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class Hypothesis(BaseModel):
    title: str                    # a possible contributing cause
    likelihood: str               # high | medium | low (given available data)
    rationale: str                # why it's plausible for this person
    supporting: list[str] = []    # evidence from the user's own data
    missing: list[str] = []       # data that would confirm/refute it


class DataGap(BaseModel):
    item: str                     # e.g. "Serum vitamin B12"
    why: str                      # why it matters for this concern
    how_to_get: str               # e.g. "Add to your next blood panel"


class InvestigationReport(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    concern: str
    generated_at: Optional[datetime] = None
    summary: str
    hypotheses: list[Hypothesis]
    data_gaps: list[DataGap]
    next_steps: list[str] = []
    disclaimer: str = (
        "This is general wellness information, not a medical diagnosis. "
        "Discuss any health concern or out-of-range result with a licensed "
        "healthcare provider."
    )
