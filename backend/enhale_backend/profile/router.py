"""User profile + symptom logging, per-user scoped."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..auth.dependencies import get_current_user
from ..db import get_session
from ..db_models import SymptomRow, User, UserProfileRow
from ..profile_models import SymptomLog, UserProfile

router = APIRouter(tags=["profile"])


@router.get("/profile", response_model=UserProfile)
async def get_profile(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> UserProfile:
    row = await session.get(UserProfileRow, user.id)
    return UserProfile.model_validate(row.payload) if row else UserProfile()


@router.put("/profile", response_model=UserProfile)
async def put_profile(
    body: UserProfile,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> UserProfile:
    body.updated_at = datetime.now(timezone.utc)
    row = await session.get(UserProfileRow, user.id)
    if row is None:
        session.add(UserProfileRow(user_id=user.id, payload=body.model_dump(mode="json"), updated_at=body.updated_at))
    else:
        row.payload = body.model_dump(mode="json")
        row.updated_at = body.updated_at
    await session.commit()
    return body


@router.post("/symptoms", response_model=SymptomLog, status_code=201)
async def add_symptom(
    body: SymptomLog,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SymptomLog:
    body.created_at = datetime.now(timezone.utc)
    session.add(SymptomRow(id=str(body.id), user_id=user.id, payload=body.model_dump(mode="json"), created_at=body.created_at))
    await session.commit()
    return body


@router.get("/symptoms", response_model=list[SymptomLog])
async def list_symptoms(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[SymptomLog]:
    rows = (
        await session.scalars(
            select(SymptomRow).where(SymptomRow.user_id == user.id).order_by(SymptomRow.created_at.desc())
        )
    ).all()
    return [SymptomLog.model_validate(r.payload) for r in rows]


@router.delete("/symptoms/{symptom_id}", status_code=204)
async def delete_symptom(
    symptom_id: str,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    row = await session.get(SymptomRow, symptom_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    await session.delete(row)
    await session.commit()
