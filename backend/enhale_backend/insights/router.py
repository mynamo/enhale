"""Insights: synthesize recommendations from the user's meals + health + labs."""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..auth.dependencies import get_current_user
from ..bloodwork_models import BloodWorkPanel
from ..db import get_session
from ..db_models import (
    BloodWorkPanelRow,
    DailyMetric,
    HealthWorkout,
    InsightReportRow,
    Meal,
    SleepNight,
    User,
)
from ..deps import get_insight_generator
from ..health_models import DailyMetricIn, HealthSummary, SleepNightIn, WorkoutIn
from ..insights.context import build_context
from ..insights.generator import InsightGenerator
from ..insights_models import InsightReport
from ..models import ParsedMeal

router = APIRouter(prefix="/insights", tags=["insights"])

_WINDOW_DAYS = 30


@router.post("/generate", response_model=InsightReport)
async def generate_insights(
    user: User = Depends(get_current_user),
    generator: InsightGenerator = Depends(get_insight_generator),
    session: AsyncSession = Depends(get_session),
) -> InsightReport:
    meals, health, panels = await _gather(session, user.id)
    context = build_context(meals, health, panels)

    report = await generator.generate(context)
    report.generated_at = datetime.now(timezone.utc)

    session.add(
        InsightReportRow(
            id=str(report.id), user_id=user.id,
            payload=report.model_dump(mode="json"), created_at=report.generated_at,
        )
    )
    await session.commit()
    return report


@router.get("", response_model=list[InsightReport])
async def list_insights(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[InsightReport]:
    rows = (
        await session.scalars(
            select(InsightReportRow)
            .where(InsightReportRow.user_id == user.id)
            .order_by(InsightReportRow.created_at.desc())
        )
    ).all()
    return [InsightReport.model_validate(r.payload) for r in rows]


async def _gather(session: AsyncSession, user_id: int):
    since_dt = datetime.now(timezone.utc) - timedelta(days=_WINDOW_DAYS)
    since_date = date.today() - timedelta(days=_WINDOW_DAYS)

    meal_rows = await session.scalars(
        select(Meal).where(Meal.user_id == user_id, Meal.eaten_at >= since_dt)
    )
    meals = [ParsedMeal.model_validate(r.payload) for r in meal_rows]

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

    return meals, health, panels
