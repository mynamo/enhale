"""Turns a raw speech transcript into a structured :class:`ParsedMeal`.

The parser is deterministic *around* the LLM: it builds a strict prompt, asks
for JSON, then decodes and resolves relative times itself so the rest of the app
works with clean typed values.
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from ..llm.client import LLMClient
from ..models import FoodItem, MealType, ParsedMeal
from . import prompts


class ParseError(Exception):
    """Base class for parse failures."""


class MalformedResponseError(ParseError):
    """The model returned text that wasn't the expected JSON object."""


class NoFoodFoundError(ParseError):
    """The transcript contained no recognizable food."""


class MealParser:
    def __init__(self, client: LLMClient) -> None:
        self._client = client

    async def parse(
        self,
        transcript: str,
        now: Optional[datetime] = None,
        tz_name: str = "UTC",
    ) -> ParsedMeal:
        """Parse ``transcript``, resolving relative times against ``now``.

        ``now`` is injected (not read from the clock) so the pipeline is fully
        testable and deterministic.
        """
        tz = ZoneInfo(tz_name)
        if now is None:
            now = datetime.now(tz)

        trimmed = transcript.strip()
        if not trimmed:
            raise NoFoodFoundError("empty transcript")

        system = prompts.SYSTEM_PROMPT
        user = prompts.user_prompt(trimmed, now, tz_name)

        raw = await self._client.complete(system=system, user=user)
        dto = _decode(raw)

        items = dto.get("items") or []
        if not items:
            raise NoFoodFoundError("no food in response")

        eaten_at = _resolve_eaten_at(
            offset_minutes=dto.get("eaten_minutes_ago"),
            iso_timestamp=dto.get("eaten_at_iso"),
            now=now,
        )

        meal_type = _coerce_meal_type(dto.get("meal_type"), eaten_at, tz)

        return ParsedMeal(
            items=[_food_item(i) for i in items],
            meal_type=meal_type,
            eaten_at=eaten_at,
            raw_transcript=trimmed,
            confidence=float(dto.get("confidence", 0.5)),
        )


# --- helpers -----------------------------------------------------------------


_MICRO_KEYS = (
    "fiber_grams", "sugar_grams", "sodium_mg", "potassium_mg", "calcium_mg",
    "iron_mg", "magnesium_mg", "zinc_mg", "vitamin_c_mg", "vitamin_d_mcg",
    "vitamin_b12_mcg", "folate_mcg", "omega3_mg",
)


def _food_item(raw: dict) -> FoodItem:
    return FoodItem(
        name=raw["name"],
        quantity=raw.get("quantity"),
        calories=raw.get("calories"),
        protein_grams=raw.get("protein_grams"),
        carb_grams=raw.get("carb_grams"),
        fat_grams=raw.get("fat_grams"),
        estimated=raw.get("estimated", True),
        **{k: raw.get(k) for k in _MICRO_KEYS},
    )


def _coerce_meal_type(raw, eaten_at: datetime, tz: ZoneInfo) -> MealType:
    try:
        return MealType(raw)
    except ValueError:
        return MealType.inferred(eaten_at.astimezone(tz).hour)


def _resolve_eaten_at(
    offset_minutes: Optional[int],
    iso_timestamp: Optional[str],
    now: datetime,
) -> datetime:
    """Prefer an explicit ISO timestamp; fall back to a relative offset; else now."""
    if iso_timestamp:
        try:
            return datetime.fromisoformat(iso_timestamp)
        except ValueError:
            pass
    if offset_minutes is not None:
        return now - timedelta(minutes=int(offset_minutes))
    return now


def _decode(raw: str) -> dict:
    """Models sometimes wrap JSON in prose or code fences. Pull out the first
    balanced ``{ ... }`` object so we're resilient to that."""
    obj = _extract_json_object(raw)
    if obj is None:
        raise MalformedResponseError(raw)
    try:
        return json.loads(obj)
    except json.JSONDecodeError as exc:
        raise MalformedResponseError(raw) from exc


def _extract_json_object(text: str) -> Optional[str]:
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    for i in range(start, len(text)):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return None
