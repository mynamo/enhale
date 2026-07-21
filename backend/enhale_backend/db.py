"""Async database engine, session dependency, and schema bootstrap.

SQLAlchemy async so it matches FastAPI's async endpoints. The engine reads
``DATABASE_URL`` from settings, so the same code runs on SQLite (dev) or
Postgres (prod) with only an env-var change.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from .config import get_settings


class Base(DeclarativeBase):
    """Base class for all ORM models."""


def _engine_config(url: str) -> tuple[str, dict]:
    """Make any managed-Postgres URL work with asyncpg.

    Managed providers (Neon, Supabase, Aiven, Render, …) require SSL and hand out
    a libpq-style ``?sslmode=require`` query param that asyncpg doesn't
    understand. Strip it and enable SSL via ``connect_args`` instead — so you can
    paste the provider's connection string verbatim into DATABASE_URL.
    """
    connect_args: dict = {}
    if "+asyncpg" not in url:
        return url, connect_args

    parts = urlsplit(url)
    query = dict(parse_qsl(parts.query))
    sslmode = query.pop("sslmode", None)
    ssl_q = query.pop("ssl", None)
    host = parts.hostname or ""
    wants_ssl = (
        (sslmode not in (None, "disable"))
        or (ssl_q not in (None, "false", "0", "disable"))
        or (host not in ("localhost", "127.0.0.1", ""))
    )
    if wants_ssl:
        connect_args["ssl"] = True
    cleaned = urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), parts.fragment))
    return cleaned, connect_args


_settings = get_settings()
_url, _connect_args = _engine_config(_settings.database_url)
engine = create_async_engine(_url, future=True, connect_args=_connect_args)
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
