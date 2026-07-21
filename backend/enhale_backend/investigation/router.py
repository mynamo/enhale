"""'Ask enhale' — investigate a concern against the user's whole dataset."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..analysis.correlations import compute_findings
from ..analysis.gather import gather_user_data
from ..auth.dependencies import get_current_user
from ..db import get_session
from ..db_models import InvestigationReportRow, User
from ..deps import get_investigation_generator
from ..insights.context import build_context
from ..investigation.generator import InvestigationGenerator
from ..investigation_models import InvestigationReport

router = APIRouter(prefix="/investigate", tags=["investigation"])


class InvestigateRequest(BaseModel):
    concern: str


@router.post("", response_model=InvestigationReport)
async def investigate(
    body: InvestigateRequest,
    user: User = Depends(get_current_user),
    generator: InvestigationGenerator = Depends(get_investigation_generator),
    session: AsyncSession = Depends(get_session),
) -> InvestigationReport:
    concern = body.concern.strip()
    if not concern:
        raise HTTPException(status_code=422, detail="Describe what you'd like to investigate")

    data = await gather_user_data(session, user.id)
    findings = compute_findings(data.meals, data.health, data.panels)
    context = build_context(
        data.meals, data.health, data.panels, data.profile, data.symptoms, findings
    )

    report = await generator.generate(concern, context)
    report.generated_at = datetime.now(timezone.utc)

    session.add(
        InvestigationReportRow(
            id=str(report.id), user_id=user.id,
            payload=report.model_dump(mode="json"), created_at=report.generated_at,
        )
    )
    await session.commit()
    return report


@router.get("", response_model=list[InvestigationReport])
async def list_investigations(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[InvestigationReport]:
    rows = (
        await session.scalars(
            select(InvestigationReportRow)
            .where(InvestigationReportRow.user_id == user.id)
            .order_by(InvestigationReportRow.created_at.desc())
        )
    ).all()
    return [InvestigationReport.model_validate(r.payload) for r in rows]
