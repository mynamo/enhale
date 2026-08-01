"""Async database engine, session dependency, and schema bootstrap.

SQLAlchemy async so it matches FastAPI's async endpoints. The engine reads
``DATABASE_URL`` from settings, so the same code runs on SQLite (dev) or
Postgres (prod) with only an env-var change.
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from .config import get_settings

logger = logging.getLogger(__name__)


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
    # Private/internal hosts (localhost, Railway's *.railway.internal, docker
    # networks) don't offer TLS — only require SSL for public managed DBs (Neon,
    # Supabase, …) or when the URL explicitly asks for it.
    is_private = host in ("localhost", "127.0.0.1", "") or host.endswith(".internal")
    explicit_ssl = (sslmode not in (None, "disable")) or (ssl_q not in (None, "false", "0", "disable"))
    if explicit_ssl or not is_private:
        connect_args["ssl"] = True
    # Disable asyncpg's prepared-statement cache so a PgBouncer/transaction-pooled
    # endpoint (e.g. Neon's "-pooler" host) works. Negligible cost for this app.
    connect_args["statement_cache_size"] = 0
    # Bound the connect attempt so a misconfigured/unreachable DB fails fast and
    # surfaces in the logs, instead of hanging (and failing the healthcheck).
    connect_args["timeout"] = 15
    cleaned = urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), parts.fragment))
    return cleaned, connect_args


_settings = get_settings()
_url, _connect_args = _engine_config(_settings.database_url)
# pool_pre_ping: verify a pooled connection is still alive before using it and
# transparently reconnect if not. Important for serverless Postgres (Neon) that
# closes idle connections when it scales to zero — avoids stale-connection 500s.
engine = create_async_engine(
    _url, future=True, connect_args=_connect_args, pool_pre_ping=True
)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency yielding a scoped async session.

    Overridable in tests via ``app.dependency_overrides[get_session]``.
    """
    async with SessionLocal() as session:
        yield session


async def init_db(retries: int = 6, delay: float = 2.0) -> None:
    """Create tables from the ORM metadata, retrying while the database comes up.

    On managed platforms the DB may not be reachable the instant the app boots
    (startup race). Retrying with a short backoff avoids a crash-on-boot that
    would fail the platform healthcheck. Fine for dev/MVP; switch to Alembic
    migrations before making schema changes in production.
    """
    import asyncio

    # Import models so they're registered on Base.metadata before create_all.
    from . import db_models  # noqa: F401

    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
            return
        except Exception as exc:  # noqa: BLE001 — retry any connection/setup error
            last_error = exc
            logger.warning("init_db attempt %d/%d failed: %s", attempt, retries, exc)
            if attempt < retries:
                await asyncio.sleep(delay)
    raise RuntimeError(f"Database not reachable after {retries} attempts") from last_error
