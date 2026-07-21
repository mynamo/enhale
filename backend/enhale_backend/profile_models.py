"""User profile + symptom logging — the context data that turns generic advice
into personalized, root-cause investigation.

Meds, supplements, smoking, and family history are essential confounders: without
them, correlations over meals/labs/sleep are easy to misread.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class UserProfile(BaseModel):
    birth_year: Optional[int] = None
    sex: Optional[str] = None          # male | female | other | unspecified
    height_cm: Optional[float] = None
    ethnicity: Optional[str] = None
    smoking: Optional[str] = None       # never | former | current
    alcohol: Optional[str] = None       # none | occasional | moderate | heavy
    medications: list[str] = []
    supplements: list[str] = []
    conditions: list[str] = []          # known diagnoses
    family_history: Optional[str] = None
    updated_at: Optional[datetime] = None


class SymptomLog(BaseModel):
    """A concern the user wants explained — powers investigation mode."""

    id: UUID = Field(default_factory=uuid4)
    name: str                           # "grey hair", "fatigue", "brain fog"
    onset: Optional[date] = None        # when it started, if known
    severity: Optional[int] = None      # 1-5
    notes: Optional[str] = None
    created_at: Optional[datetime] = None
