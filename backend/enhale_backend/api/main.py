"""FastAPI application: the HTTP seam every client (iOS, web, Android) talks to.

The OpenAPI schema generated from these routers + the Pydantic models is the
shared contract — clients share this API, not Python source.
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI

from ..auth.router import router as auth_router
from ..bloodwork.router import router as bloodwork_router
from ..db import init_db
from ..health.router import router as health_router
from ..insights.router import router as insights_router
from ..investigation.router import router as investigation_router
from ..meals.router import router as meals_router
from ..profile.router import router as profile_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Dev/MVP: create tables on startup. Switch to Alembic migrations before
    # making schema changes in production.
    await init_db()
    yield


app = FastAPI(title="enhale backend", version="0.2.0", lifespan=lifespan)


@app.get("/")
async def root() -> dict:
    return {"service": "enhale", "status": "ok", "docs": "/docs", "health": "/health"}


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


app.include_router(auth_router)
app.include_router(meals_router)
app.include_router(health_router)
app.include_router(bloodwork_router)
app.include_router(insights_router)
app.include_router(profile_router)
app.include_router(investigation_router)
