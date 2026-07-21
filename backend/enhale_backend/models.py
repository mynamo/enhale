"""Domain models for enhale.

These Pydantic models are the single source of truth for the API contract:
FastAPI derives the OpenAPI schema from them, and every client (iOS, web,
Android) conforms to that schema. Keep them platform-neutral — no framework or
transport concerns leak in here.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class MealType(str, Enum):
    """Which eating occasion a logged item belongs to.

    ``unspecified`` is the safe default when the user didn't say and the time of
    day is ambiguous — never guess a meal type with false confidence.
    """

    breakfast = "breakfast"
    lunch = "lunch"
    dinner = "dinner"
    snack = "snack"
    unspecified = "unspecified"

    @classmethod
    def inferred(cls, hour: int) -> "MealType":
        """A reasonable default from a wall-clock hour, used only when the
        transcript gives no explicit signal."""
        if 5 <= hour < 11:
            return cls.breakfast
        if 11 <= hour < 15:
            return cls.lunch
        if 17 <= hour < 22:
            return cls.dinner
        return cls.snack


class FoodItem(BaseModel):
    """A single food or drink within a meal, with a rough nutrition estimate.

    Nutrition fields are optional: the LLM estimates where it can and leaves
    fields ``None`` rather than fabricating. ``estimated`` marks model guesses
    vs. numbers the user stated.
    """

    id: UUID = Field(default_factory=uuid4)
    name: str
    quantity: Optional[str] = None
    calories: Optional[float] = None
    protein_grams: Optional[float] = None
    carb_grams: Optional[float] = None
    fat_grams: Optional[float] = None
    # Micronutrients & other components (estimated). All optional — the model
    # fills what it reasonably can and leaves the rest null.
    fiber_grams: Optional[float] = None
    sugar_grams: Optional[float] = None
    sodium_mg: Optional[float] = None
    potassium_mg: Optional[float] = None
    calcium_mg: Optional[float] = None
    iron_mg: Optional[float] = None
    magnesium_mg: Optional[float] = None
    zinc_mg: Optional[float] = None
    vitamin_c_mg: Optional[float] = None
    vitamin_d_mcg: Optional[float] = None
    vitamin_b12_mcg: Optional[float] = None
    folate_mcg: Optional[float] = None
    omega3_mg: Optional[float] = None
    estimated: bool = True


class ParsedMeal(BaseModel):
    """The structured result of parsing one spoken log entry."""

    id: UUID = Field(default_factory=uuid4)
    items: list[FoodItem]
    meal_type: MealType
    eaten_at: datetime
    raw_transcript: str
    confidence: float

    @property
    def total_calories(self) -> float:
        """Sum of per-item calories, ignoring items where it's unknown."""
        return sum(item.calories for item in self.items if item.calories is not None)
