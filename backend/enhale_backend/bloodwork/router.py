"""Blood work: upload a lab report (PDF/PNG/JPEG), extract markers, store, read.

All routes are scoped to the authenticated user. The uploaded file itself is
*not* stored — only the structured markers extracted from it (sensitive data:
keep the footprint minimal).
"""

from __future__ import annotations

import base64
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..auth.dependencies import get_current_user
from ..bloodwork.extractor import BloodWorkExtractor
from ..bloodwork_models import BloodWorkPanel
from ..db import get_session
from ..db_models import BloodWorkPanelRow, User
from ..deps import get_bloodwork_extractor

router = APIRouter(prefix="/bloodwork", tags=["bloodwork"])

_MAX_BYTES = 10 * 1024 * 1024  # 10 MB
_ALLOWED = {
    "application/pdf": "application/pdf",
    "image/png": "image/png",
    "image/jpeg": "image/jpeg",
    "image/jpg": "image/jpeg",
}


@router.post("/upload", response_model=BloodWorkPanel)
async def upload(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    extractor: BloodWorkExtractor = Depends(get_bloodwork_extractor),
    session: AsyncSession = Depends(get_session),
) -> BloodWorkPanel:
    media_type = _media_type(file)
    data = await file.read()
    if len(data) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 10 MB)")
    if not data:
        raise HTTPException(status_code=400, detail="Empty file")

    b64 = base64.standard_b64encode(data).decode("ascii")
    panel = await extractor.extract(file.filename or "upload", media_type, b64)
    panel.created_at = datetime.now(timezone.utc)

    session.add(
        BloodWorkPanelRow(
            id=str(panel.id),
            user_id=user.id,
            collected_on=panel.collected_on,
            source_filename=panel.source_filename,
            payload=panel.model_dump(mode="json"),
            created_at=panel.created_at,
        )
    )
    await session.commit()
    return panel


@router.get("", response_model=list[BloodWorkPanel])
async def list_panels(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[BloodWorkPanel]:
    rows = (
        await session.scalars(
            select(BloodWorkPanelRow)
            .where(BloodWorkPanelRow.user_id == user.id)
            .order_by(BloodWorkPanelRow.created_at.desc())
        )
    ).all()
    return [BloodWorkPanel.model_validate(r.payload) for r in rows]


@router.delete("/{panel_id}", status_code=204)
async def delete_panel(
    panel_id: str,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    row = await session.get(BloodWorkPanelRow, panel_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    await session.delete(row)
    await session.commit()


def _media_type(file: UploadFile) -> str:
    ct = (file.content_type or "").lower()
    if ct in _ALLOWED:
        return _ALLOWED[ct]
    name = (file.filename or "").lower()
    if name.endswith(".pdf"):
        return "application/pdf"
    if name.endswith(".png"):
        return "image/png"
    if name.endswith((".jpg", ".jpeg")):
        return "image/jpeg"
    raise HTTPException(status_code=415, detail="Unsupported file type; use PDF, PNG, or JPEG")
