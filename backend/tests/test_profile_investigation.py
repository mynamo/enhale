"""Tests for profile, symptoms, correlations, micros, and investigation mode."""

from __future__ import annotations

from datetime import datetime, timezone

import pytest

from enhale_backend.analysis.correlations import compute_findings
from enhale_backend.api.main import app
from enhale_backend.bloodwork_models import BloodMarker, BloodWorkPanel
from enhale_backend.deps import get_investigation_generator
from enhale_backend.health_models import DailyMetricIn, HealthSummary, SleepNightIn
from enhale_backend.investigation.generator import InvestigationGenerator
from enhale_backend.models import FoodItem, MealType, ParsedMeal

INVESTIGATION_JSON = """
{"summary":"Grey hair is usually genetic but a few reversible factors are worth ruling out.",
 "hypotheses":[
   {"title":"Vitamin B12 deficiency","likelihood":"medium","rationale":"Diet is low in animal protein.","supporting":["Low B12 intake in logged meals"],"missing":["Serum B12 level"]},
   {"title":"Genetics","likelihood":"high","rationale":"Most common cause.","supporting":[],"missing":["Family history / age of onset"]}
 ],
 "data_gaps":[
   {"item":"Serum vitamin B12","why":"Low B12 is a reversible cause of premature greying","how_to_get":"Add to your next blood panel"}
 ],
 "next_steps":["Ask your doctor to test B12, ferritin, and copper"]}
"""


# --- profile + symptoms -------------------------------------------------------


def test_profile_upsert_and_get(client, auth):
    headers = auth()
    assert client.get("/profile", headers=headers).json()["medications"] == []

    r = client.put("/profile", headers=headers, json={
        "birth_year": 1990, "sex": "female", "smoking": "never",
        "medications": ["levothyroxine"], "supplements": ["vitamin D"],
        "family_history": "mother greyed early",
    })
    assert r.status_code == 200
    got = client.get("/profile", headers=headers).json()
    assert got["birth_year"] == 1990
    assert got["medications"] == ["levothyroxine"]
    assert got["updated_at"]


def test_symptom_crud_and_isolation(client, auth):
    alice = auth(email="sa@y.com")
    bob = auth(email="sb@y.com")

    sid = client.post("/symptoms", headers=alice, json={"name": "grey hair", "severity": 3}).json()["id"]
    assert len(client.get("/symptoms", headers=alice).json()) == 1
    assert client.get("/symptoms", headers=bob).json() == []
    assert client.delete(f"/symptoms/{sid}", headers=bob).status_code == 404
    assert client.delete(f"/symptoms/{sid}", headers=alice).status_code == 204


# --- micros in parsing --------------------------------------------------------


def test_meal_parse_captures_micros(client, stub_parser, auth):
    stub_parser(
        '{"items":[{"name":"spinach","calories":23,"iron_mg":2.7,"folate_mcg":194,"vitamin_c_mg":28,"estimated":true}],'
        '"meal_type":"lunch","confidence":0.9}'
    )
    headers = auth()
    meal = client.post("/meals/parse", json={"transcript": "a bowl of spinach"}, headers=headers).json()
    item = meal["items"][0]
    assert item["iron_mg"] == 2.7 and item["folate_mcg"] == 194 and item["vitamin_c_mg"] == 28


# --- correlation engine (pure) ------------------------------------------------


def test_compute_findings_detects_patterns():
    late = datetime(2026, 7, 20, 22, 0, tzinfo=timezone.utc)
    meals = [
        ParsedMeal(items=[FoodItem(name="pizza", calories=800)], meal_type=MealType.dinner,
                   eaten_at=late, raw_transcript="pizza", confidence=0.9),
        ParsedMeal(items=[FoodItem(name="burger", calories=700)], meal_type=MealType.dinner,
                   eaten_at=late.replace(day=19), raw_transcript="burger", confidence=0.9),
        ParsedMeal(items=[FoodItem(name="fries", calories=400)], meal_type=MealType.snack,
                   eaten_at=late.replace(day=18), raw_transcript="fries", confidence=0.9),
    ]
    health = HealthSummary(
        workouts=[], sleep=[SleepNightIn(date=f"2026-07-{d}", asleep_seconds=5 * 3600) for d in (18, 19, 20)],
        daily=[DailyMetricIn(date=f"2026-07-{d}", steps=3000, resting_heart_rate=70) for d in (18, 19, 20)],
    )
    findings = compute_findings(meals, health, [])
    text = " ".join(findings)
    assert "late-night" in text
    assert "sleep" in text.lower()


def test_lab_trajectory_across_panels():
    panels = [
        BloodWorkPanel(collected_on="2026-07-01", source_filename="b.pdf",
                       markers=[BloodMarker(name="LDL", value="161", value_num=161)]),
        BloodWorkPanel(collected_on="2026-01-01", source_filename="a.pdf",
                       markers=[BloodMarker(name="LDL", value="130", value_num=130)]),
    ]
    findings = compute_findings([], HealthSummary(workouts=[], sleep=[], daily=[]), panels)
    assert any("LDL trending up" in f for f in findings)


# --- investigation ------------------------------------------------------------


@pytest.fixture
def stub_investigator():
    def _set(response: str = INVESTIGATION_JSON):
        stub = _StubLLM(response)
        app.dependency_overrides[get_investigation_generator] = lambda: InvestigationGenerator(stub)
        return stub
    return _set


class _StubLLM:
    def __init__(self, response: str) -> None:
        self.response = response
        self.last_user: str | None = None

    async def complete(self, system: str, user: str) -> str:
        self.last_user = user
        return self.response


def test_investigate_requires_auth(client, stub_investigator):
    stub_investigator()
    assert client.post("/investigate", json={"concern": "grey hair"}).status_code == 401


def test_investigate_returns_hypotheses_and_gaps(client, stub_investigator, auth):
    stub_investigator()
    headers = auth()

    r = client.post("/investigate", json={"concern": "why do I have grey hair?"}, headers=headers)
    assert r.status_code == 200
    report = r.json()
    assert report["concern"].startswith("why")
    assert len(report["hypotheses"]) == 2
    assert report["data_gaps"][0]["item"] == "Serum vitamin B12"
    assert report["next_steps"]
    assert report["generated_at"] and "disclaimer" in report

    assert len(client.get("/investigate", headers=headers).json()) == 1


def test_investigate_includes_profile_and_symptoms_in_prompt(client, stub_investigator, auth):
    stub = stub_investigator()
    headers = auth()
    client.put("/profile", headers=headers, json={"smoking": "current", "family_history": "dad greyed at 25"})
    client.post("/symptoms", headers=headers, json={"name": "grey hair"})

    client.post("/investigate", json={"concern": "grey hair"}, headers=headers)
    prompt = stub.last_user or ""
    assert "smoking: current" in prompt and "dad greyed at 25" in prompt


def test_investigate_empty_concern_rejected(client, stub_investigator, auth):
    stub_investigator()
    headers = auth()
    assert client.post("/investigate", json={"concern": "   "}, headers=headers).status_code == 422
