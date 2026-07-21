"""Health data contract — what clients (iOS HealthKit, future Android Health
Connect) send to and receive from the backend.

Kept platform-neutral: an iOS app fills these from HealthKit, an Android app
from Health Connect, both conforming to the same schema.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Optional

from pydantic import BaseModel, field_serializer


class WorkoutIn(BaseModel):
    """A single workout session (e.g. an Apple Watch run)."""

    id: str  # HealthKit sample UUID — stable, used for idempotent upserts
    workout_type: str  # "running", "walking", "cycling", "strength", ...
    start_at: datetime
    end_at: datetime
    duration_seconds: float
    active_energy_kcal: Optional[float] = None
    distance_meters: Optional[float] = None
    source: Optional[str] = None  # "Apple Watch", "iPhone", ...

    @field_serializer("start_at", "end_at")
    def _serialize_utc(self, dt: datetime) -> str:
        # SQLite drops tzinfo, so datetimes read back naive. Treat naive as UTC
        # and always emit a `Z` suffix so every client decodes consistently.
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class SleepNightIn(BaseModel):
    """A nightly sleep summary, aggregated on-device from raw sleep samples."""

    date: date  # the calendar date the night is attributed to (wake day)
    in_bed_seconds: Optional[float] = None
    asleep_seconds: float
    rem_seconds: Optional[float] = None
    deep_seconds: Optional[float] = None
    core_seconds: Optional[float] = None
    awake_seconds: Optional[float] = None


class DailyMetricIn(BaseModel):
    """Per-day activity/vitals rollup."""

    date: date
    steps: Optional[int] = None
    active_energy_kcal: Optional[float] = None
    resting_energy_kcal: Optional[float] = None
    resting_heart_rate: Optional[float] = None
    hrv_ms: Optional[float] = None
    body_mass_kg: Optional[float] = None


class HealthSyncRequest(BaseModel):
    """Batch the client pushes on each sync. All lists optional/partial —
    the client sends whatever it has since the last sync."""

    workouts: list[WorkoutIn] = []
    sleep: list[SleepNightIn] = []
    daily: list[DailyMetricIn] = []


class HealthSyncResult(BaseModel):
    workouts_upserted: int
    sleep_upserted: int
    daily_upserted: int


class HealthSummary(BaseModel):
    """Read model: a compact recent view for the app to display."""

    workouts: list[WorkoutIn]
    sleep: list[SleepNightIn]
    daily: list[DailyMetricIn]
