"""Tests for /insights: generation (stubbed LLM), storage, and context building."""

from __future__ import annotations

from datetime import datetime, timezone

import pytest

from enhale_backend.api.main import app
from enhale_backend.bloodwork_models import BloodMarker, BloodWorkPanel
from enhale_backend.deps import get_insight_generator
from enhale_backend.health_models import DailyMetricIn, HealthSummary, WorkoutIn
from enhale_backend.insights.context import build_context
from enhale_backend.insights.generator import InsightGenerator
from enhale_backend.models import FoodItem, MealType, ParsedMeal

REPORT_JSON = """
{"summary":"You're active but eating late.",
 "observations":["Dinners often after 9pm","LDL is elevated"],
 "recommendations":[
   {"title":"Eat dinner earlier","detail":"Aim to finish by 8pm.","category":"nutrition","priority":"high","rationale":"Several late dinners logged"},
   {"title":"Discuss LDL with your doctor","detail":"Your LDL is above range.","category":"labs","priority":"high","rationale":"LDL 161 flagged high"}
 ]}
"""


class StubLLM:
    def __init__(self, response: str) -> None:
        self.response = response
        self.last_user: str | None = None

    async def complete(self, system: str, user: str) -> str:
        self.last_user = user
        return self.response


@pytest.fixture
def stub_generator():
    def _set(response: str = REPORT_JSON) -> StubLLM:
        stub = StubLLM(response)
        app.dependency_overrides[get_insight_generator] = lambda: InsightGenerator(stub)
        return stub
    return _set


def test_generate_requires_auth(client, stub_generator):
    stub_generator()
    assert client.post("/insights/generate").status_code == 401


def test_generate_and_list(client, stub_generator, auth):
    stub_generator()
    headers = auth()

    r = client.post("/insights/generate", headers=headers)
    assert r.status_code == 200
    report = r.json()
    assert report["summary"].startswith("You're active")
    assert len(report["recommendations"]) == 2
    assert report["recommendations"][0]["category"] == "nutrition"
    assert "disclaimer" in report and report["generated_at"]

    listed = client.get("/insights", headers=headers).json()
    assert len(listed) == 1
    assert listed[0]["id"] == report["id"]


def test_generate_feeds_logged_data_into_prompt(client, stub_generator, auth):
    stub = stub_generator()
    headers = auth()

    # Log a meal so the context includes it.
    from tests.conftest import StubLLMClient  # reuse meal-parser stub
    from enhale_backend.deps import get_parser
    from enhale_backend.parsing.meal_parser import MealParser
    app.dependency_overrides[get_parser] = lambda: MealParser(
        StubLLMClient('{"items":[{"name":"pizza","estimated":true}],"meal_type":"dinner","confidence":0.9}')
    )
    client.post("/meals/parse", json={"transcript": "pizza"}, headers=headers)

    client.post("/insights/generate", headers=headers)
    assert "pizza" in (stub.last_user or "")  # the meal reached the LLM prompt


def test_build_context_summarizes_all_sources():
    meals = [ParsedMeal(
        items=[FoodItem(name="oatmeal", calories=150)], meal_type=MealType.breakfast,
        eaten_at=datetime(2026, 7, 20, 8, 0, tzinfo=timezone.utc),
        raw_transcript="oatmeal", confidence=0.9,
    )]
    health = HealthSummary(
        workouts=[WorkoutIn(id="w1", workout_type="running",
                            start_at=datetime(2026, 7, 20, 6, tzinfo=timezone.utc),
                            end_at=datetime(2026, 7, 20, 6, 30, tzinfo=timezone.utc),
                            duration_seconds=1800, active_energy_kcal=250)],
        sleep=[], daily=[DailyMetricIn(date="2026-07-20", steps=9000)],
    )
    panels = [BloodWorkPanel(source_filename="labs.pdf",
                             markers=[BloodMarker(name="LDL", value="161", value_num=161, unit="mg/dL", flag="high")])]

    ctx = build_context(meals, health, panels)
    assert "oatmeal" in ctx and "running" in ctx and "9000 steps" in ctx and "LDL" in ctx and "[HIGH]" in ctx
