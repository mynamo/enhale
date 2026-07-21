"""Per-user health data: sync from the client, read a recent summary back.

The client (iOS HealthKit today, Android Health Connect later) reads native
health data and pushes it here. Everything is scoped to the authenticated user.
Syncs are idempotent — workouts key on their sample id, sleep/daily on
(user, date) — so the client can safely re-send overlapping ranges.
"""

from __future__ import annotations

from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..auth.dependencies import get_current_user
from ..db import get_session
from ..db_models import DailyMetric, HealthWorkout, SleepNight, User
from ..health_models import (
    DailyMetricIn,
    HealthSummary,
    HealthSyncRequest,
    HealthSyncResult,
    SleepNightIn,
    WorkoutIn,
)

router = APIRouter(prefix="/health", tags=["health"])


@router.post("/sync", response_model=HealthSyncResult)
async def sync_health(
    body: HealthSyncRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> HealthSyncResult:
    for w in body.workouts:
        existing = await session.get(HealthWorkout, w.id)
        if existing is not None and existing.user_id != user.id:
            continue  # never touch another user's row (id collisions ~impossible)
        row = existing or HealthWorkout(id=w.id, user_id=user.id)
        row.workout_type = w.workout_type
        row.start_at = w.start_at
        row.end_at = w.end_at
        row.duration_seconds = w.duration_seconds
        row.active_energy_kcal = w.active_energy_kcal
        row.distance_meters = w.distance_meters
        row.source = w.source
        if existing is None:
            session.add(row)  # a loaded row is already tracked; only add new ones

    for s in body.sleep:
        row = await _get_by_user_date(session, SleepNight, user.id, s.date)
        row = row or SleepNight(user_id=user.id, date=s.date)
        row.in_bed_seconds = s.in_bed_seconds
        row.asleep_seconds = s.asleep_seconds
        row.rem_seconds = s.rem_seconds
        row.deep_seconds = s.deep_seconds
        row.core_seconds = s.core_seconds
        row.awake_seconds = s.awake_seconds
        session.add(row)

    for d in body.daily:
        row = await _get_by_user_date(session, DailyMetric, user.id, d.date)
        row = row or DailyMetric(user_id=user.id, date=d.date)
        row.steps = d.steps
        row.active_energy_kcal = d.active_energy_kcal
        row.resting_energy_kcal = d.resting_energy_kcal
        row.resting_heart_rate = d.resting_heart_rate
        row.hrv_ms = d.hrv_ms
        row.body_mass_kg = d.body_mass_kg
        session.add(row)

    await session.commit()
    return HealthSyncResult(
        workouts_upserted=len(body.workouts),
        sleep_upserted=len(body.sleep),
        daily_upserted=len(body.daily),
    )


@router.get("/summary", response_model=HealthSummary)
async def health_summary(
    days: int = 14,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> HealthSummary:
    """Recent workouts, sleep, and daily metrics for the last ``days`` days."""
    since_date = date.today() - timedelta(days=days)

    workouts = (
        await session.scalars(
            select(HealthWorkout)
            .where(HealthWorkout.user_id == user.id)
            .order_by(HealthWorkout.start_at.desc())
            .limit(100)
        )
    ).all()
    sleep = (
        await session.scalars(
            select(SleepNight)
            .where(SleepNight.user_id == user.id, SleepNight.date >= since_date)
            .order_by(SleepNight.date.desc())
        )
    ).all()
    daily = (
        await session.scalars(
            select(DailyMetric)
            .where(DailyMetric.user_id == user.id, DailyMetric.date >= since_date)
            .order_by(DailyMetric.date.desc())
        )
    ).all()

    return HealthSummary(
        workouts=[WorkoutIn.model_validate(w, from_attributes=True) for w in workouts],
        sleep=[SleepNightIn.model_validate(s, from_attributes=True) for s in sleep],
        daily=[DailyMetricIn.model_validate(d, from_attributes=True) for d in daily],
    )


async def _get_by_user_date(session: AsyncSession, model, user_id: int, day: date):
    return await session.scalar(
        select(model).where(model.user_id == user_id, model.date == day)
    )
