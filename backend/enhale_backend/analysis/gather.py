"""Gather all of a user's data for analysis (insights + investigation)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..bloodwork_models import BloodWorkPanel
from ..db_models import (
    BloodWorkPanelRow,
    DailyMetric,
    HealthWorkout,
    Meal,
    SleepNight,
    SymptomRow,
    UserProfileRow,
)
from ..health_models import DailyMetricIn, HealthSummary, SleepNightIn, WorkoutIn
from ..models import ParsedMeal
from ..profile_models import SymptomLog, UserProfile


@dataclass
class UserData:
    meals: list[ParsedMeal]
    health: HealthSummary
    panels: list[BloodWorkPanel]
    profile: UserProfile
    symptoms: list[SymptomLog]


async def gather_user_data(session: AsyncSession, user_id: int, window_days: int = 30) -> UserData:
    since_dt = datetime.now(timezone.utc) - timedelta(days=window_days)
    since_date = date.today() - timedelta(days=window_days)

    meals = [
        ParsedMeal.model_validate(r.payload)
        for r in await session.scalars(
            select(Meal).where(Meal.user_id == user_id, Meal.eaten_at >= since_dt)
        )
    ]

    workouts = [
        WorkoutIn.model_validate(w, from_attributes=True)
        for w in await session.scalars(
            select(HealthWorkout).where(HealthWorkout.user_id == user_id)
            .order_by(HealthWorkout.start_at.desc()).limit(100)
        )
    ]
    sleep = [
        SleepNightIn.model_validate(s, from_attributes=True)
        for s in await session.scalars(
            select(SleepNight).where(SleepNight.user_id == user_id, SleepNight.date >= since_date)
            .order_by(SleepNight.date.desc())
        )
    ]
    daily = [
        DailyMetricIn.model_validate(d, from_attributes=True)
        for d in await session.scalars(
            select(DailyMetric).where(DailyMetric.user_id == user_id, DailyMetric.date >= since_date)
            .order_by(DailyMetric.date.desc())
        )
    ]
    health = HealthSummary(workouts=workouts, sleep=sleep, daily=daily)

    panels = [
        BloodWorkPanel.model_validate(r.payload)
        for r in await session.scalars(
            select(BloodWorkPanelRow).where(BloodWorkPanelRow.user_id == user_id)
            .order_by(BloodWorkPanelRow.created_at.desc())
        )
    ]

    profile_row = await session.get(UserProfileRow, user_id)
    profile = UserProfile.model_validate(profile_row.payload) if profile_row else UserProfile()

    symptoms = [
        SymptomLog.model_validate(r.payload)
        for r in await session.scalars(
            select(SymptomRow).where(SymptomRow.user_id == user_id).order_by(SymptomRow.created_at.desc())
        )
    ]

    return UserData(meals=meals, health=health, panels=panels, profile=profile, symptoms=symptoms)
