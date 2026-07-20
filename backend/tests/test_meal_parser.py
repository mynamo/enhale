"""Parser tests using a stub LLM — no network, fully deterministic."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from enhale_backend.models import MealType
from enhale_backend.parsing.meal_parser import (
    MalformedResponseError,
    MealParser,
    NoFoodFoundError,
)

# Fixed reference time: 2026-07-19 08:30:00 UTC.
NOW = datetime(2026, 7, 19, 8, 30, tzinfo=timezone.utc)


class StubLLMClient:
    """Returns whatever JSON the test hands it; records the prompt it saw."""

    def __init__(self, response: str) -> None:
        self.response = response
        self.last_system: str | None = None
        self.last_user: str | None = None

    async def complete(self, system: str, user: str) -> str:
        self.last_system = system
        self.last_user = user
        return self.response


@pytest.mark.asyncio
async def test_parses_basic_meal_with_items():
    json = """
    {"items":[
      {"name":"scrambled eggs","quantity":"two","calories":180,"protein_grams":12,"carb_grams":2,"fat_grams":13,"estimated":true},
      {"name":"black coffee","quantity":"a cup","calories":5,"estimated":true}
    ],"meal_type":"breakfast","eaten_minutes_ago":null,"eaten_at_iso":null,"confidence":0.9}
    """
    parser = MealParser(StubLLMClient(json))

    meal = await parser.parse("two scrambled eggs and a coffee", now=NOW)

    assert len(meal.items) == 2
    assert meal.items[0].name == "scrambled eggs"
    assert meal.meal_type == MealType.breakfast
    assert meal.total_calories == 185
    assert meal.eaten_at == NOW  # no time given -> defaults to now
    assert meal.confidence == pytest.approx(0.9)


@pytest.mark.asyncio
async def test_resolves_relative_time():
    json = '{"items":[{"name":"banana","estimated":true}],"meal_type":null,"eaten_minutes_ago":60,"eaten_at_iso":null,"confidence":0.7}'
    parser = MealParser(StubLLMClient(json))

    meal = await parser.parse("a banana an hour ago", now=NOW)

    assert meal.eaten_at == NOW - timedelta(minutes=60)


@pytest.mark.asyncio
async def test_infers_meal_type_from_resolved_hour_when_null():
    # eaten at 08:30 UTC, model gave no meal_type -> inferred breakfast.
    json = '{"items":[{"name":"toast","estimated":true}],"meal_type":null,"eaten_minutes_ago":null,"eaten_at_iso":null,"confidence":0.5}'
    parser = MealParser(StubLLMClient(json))

    meal = await parser.parse("some toast", now=NOW)

    assert meal.meal_type == MealType.breakfast


@pytest.mark.asyncio
async def test_extracts_json_wrapped_in_prose_and_fences():
    json = """
    Sure! Here is the structured meal:
    ```json
    {"items":[{"name":"apple","estimated":true}],"confidence":0.8}
    ```
    Let me know if you need anything else.
    """
    parser = MealParser(StubLLMClient(json))

    meal = await parser.parse("an apple", now=NOW)

    assert meal.items[0].name == "apple"


@pytest.mark.asyncio
async def test_empty_transcript_raises():
    parser = MealParser(StubLLMClient("{}"))
    with pytest.raises(NoFoodFoundError):
        await parser.parse("   ", now=NOW)


@pytest.mark.asyncio
async def test_no_food_in_response_raises():
    parser = MealParser(StubLLMClient('{"items":[],"confidence":0}'))
    with pytest.raises(NoFoodFoundError):
        await parser.parse("hello there", now=NOW)


@pytest.mark.asyncio
async def test_malformed_response_raises():
    parser = MealParser(StubLLMClient("not json at all"))
    with pytest.raises(MalformedResponseError):
        await parser.parse("an apple", now=NOW)


@pytest.mark.asyncio
async def test_prompt_includes_transcript_and_time():
    stub = StubLLMClient('{"items":[{"name":"tea","estimated":true}],"confidence":0.5}')
    parser = MealParser(stub)

    await parser.parse("a cup of tea", now=NOW)

    assert "a cup of tea" in (stub.last_user or "")
    assert "2026-07-19" in (stub.last_user or "")
