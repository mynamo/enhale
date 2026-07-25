"""Blood work: upload a lab report (PDF/PNG/JPEG), extract markers, store, read.

All routes are scoped to the authenticated user. The uploaded file itself is
*not* stored — only the structured markers extracted from it (sensitive data:
keep the footprint minimal).
"""

from __future__ import annotations

import base64
import io
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger(__name__)

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

    data, media_type = _downscale_if_image(data, media_type)
    b64 = base64.standard_b64encode(data).decode("ascii")
    try:
        panel = await extractor.extract(file.filename or "upload", media_type, b64)
    except HTTPException:
        raise
    except Exception:
        # Surfaces the real traceback in the server logs; returns a helpful,
        # non-500 message so the user knows what to try instead.
        logger.exception("Blood work extraction failed for %s (%s)", file.filename, media_type)
        raise HTTPException(
            status_code=502,
            detail="Couldn't read that report. Try a clearer photo, a single page, or a smaller file.",
        )
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


def _downscale_if_image(data: bytes, media_type: str) -> tuple[bytes, str]:
    """Phone photos are often several MB / 4000+ px, which can exceed the vision
    API's per-image size limit and 500 the request. Downscale to a long edge the
    model reads well and re-encode as JPEG. PDFs pass through untouched; if
    anything fails we fall back to the original bytes."""
    if media_type == "application/pdf":
        return data, media_type
    try:
        from PIL import Image

        img = Image.open(io.BytesIO(data)).convert("RGB")
        max_edge = 1568  # the vision API's optimal long edge
        if max(img.size) > max_edge:
            img.thumbnail((max_edge, max_edge))
        out = io.BytesIO()
        img.save(out, format="JPEG", quality=85)
        return out.getvalue(), "image/jpeg"
    except Exception:
        logger.warning("Image downscale failed; sending original bytes", exc_info=True)
        return data, media_type


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
