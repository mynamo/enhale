"""Insights: synthesize recommendations from the user's meals + health + labs."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..analysis.correlations import compute_findings
from ..analysis.gather import gather_user_data
from ..auth.dependencies import get_current_user
from ..db import get_session
from ..db_models import InsightReportRow, User
from ..deps import get_insight_generator
from ..insights.context import build_context
from ..insights.generator import InsightGenerator
from ..insights_models import InsightReport

router = APIRouter(prefix="/insights", tags=["insights"])


@router.post("/generate", response_model=InsightReport)
async def generate_insights(
    user: User = Depends(get_current_user),
    generator: InsightGenerator = Depends(get_insight_generator),
    session: AsyncSession = Depends(get_session),
) -> InsightReport:
    data = await gather_user_data(session, user.id)
    findings = compute_findings(data.meals, data.health, data.panels)
    context = build_context(
        data.meals, data.health, data.panels, data.profile, data.symptoms, findings
    )

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
