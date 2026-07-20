"""Async database engine, session dependency, and schema bootstrap.

SQLAlchemy async so it matches FastAPI's async endpoints. The engine reads
``DATABASE_URL`` from settings, so the same code runs on SQLite (dev) or
Postgres (prod) with only an env-var change.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from .config import get_settings


class Base(DeclarativeBase):
    """Base class for all ORM models."""


_settings = get_settings()
engine = create_async_engine(_settings.database_url, future=True)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency yielding a scoped async session.

    Overridable in tests via ``app.dependency_overrides[get_session]``.
    """
    async with SessionLocal() as session:
        yield session


async def init_db() -> None:
    """Create tables from the ORM metadata.

    Fine for dev/MVP. Before making schema changes in production, switch to
    Alembic migrations (already a declared dependency) instead of create_all.
    """
    # Import models so they're registered on Base.metadata before create_all.
    from . import db_models  # noqa: F401

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
