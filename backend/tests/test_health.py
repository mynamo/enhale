"""Tests for the /health sync + summary endpoints."""

from __future__ import annotations


def _workout(wid="wk-1", wtype="running"):
    return {
        "id": wid,
        "workout_type": wtype,
        "start_at": "2026-07-20T06:00:00Z",
        "end_at": "2026-07-20T06:30:00Z",
        "duration_seconds": 1800,
        "active_energy_kcal": 250,
        "distance_meters": 5000,
        "source": "Apple Watch",
    }


def _sleep(day="2026-07-20", asleep=27000.0):
    return {"date": day, "in_bed_seconds": 30000, "asleep_seconds": asleep, "rem_seconds": 6000}


def _daily(day="2026-07-20", steps=8000):
    return {"date": day, "steps": steps, "active_energy_kcal": 500, "resting_heart_rate": 58}


def test_sync_requires_auth(client):
    assert client.post("/health/sync", json={"workouts": [_workout()]}).status_code == 401


def test_sync_and_summary(client, auth):
    headers = auth()
    body = {"workouts": [_workout()], "sleep": [_sleep()], "daily": [_daily()]}

    r = client.post("/health/sync", json=body, headers=headers)
    assert r.status_code == 200
    assert r.json() == {"workouts_upserted": 1, "sleep_upserted": 1, "daily_upserted": 1}

    r = client.get("/health/summary?days=3650", headers=headers)
    assert r.status_code == 200
    data = r.json()
    assert len(data["workouts"]) == 1
    assert data["workouts"][0]["workout_type"] == "running"
    assert len(data["sleep"]) == 1
    assert data["daily"][0]["steps"] == 8000


def test_sync_is_idempotent(client, auth):
    headers = auth()
    # Same workout id + same day, sent twice with changed values → upsert, not dup.
    client.post("/health/sync", json={"workouts": [_workout()], "daily": [_daily(steps=1000)]}, headers=headers)
    client.post("/health/sync", json={"workouts": [_workout()], "daily": [_daily(steps=9999)]}, headers=headers)

    data = client.get("/health/summary?days=3650", headers=headers).json()
    assert len(data["workouts"]) == 1          # not duplicated
    assert len(data["daily"]) == 1             # (user, date) upserted
    assert data["daily"][0]["steps"] == 9999   # latest value wins


def test_health_is_isolated_per_user(client, auth):
    alice = auth(email="halice@y.com")
    bob = auth(email="hbob@y.com")

    client.post("/health/sync", json={"workouts": [_workout()], "daily": [_daily()]}, headers=alice)

    assert len(client.get("/health/summary?days=3650", headers=alice).json()["workouts"]) == 1
    bob_data = client.get("/health/summary?days=3650", headers=bob).json()
    assert bob_data["workouts"] == [] and bob_data["daily"] == []
