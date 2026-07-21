"""Runtime configuration, read from the environment.

Kept dependency-free (plain ``os.environ``) so importing the package never
requires secrets to be present — only the endpoints that actually use them fail
if they're missing.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-opus-4-8"

    # SQLite for local dev (zero setup); swap to Postgres in prod by setting
    # DATABASE_URL=postgresql+asyncpg://user:pass@host/db — no code changes.
    database_url: str = "sqlite+aiosqlite:///./enhale.db"

    # JWT signing. MUST be overridden in any real deployment.
    jwt_secret: str = "dev-insecure-change-me-32bytes-minimum!!"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7  # one week


def _normalize_db_url(url: str) -> str:
    """Managed Postgres providers (Render, Heroku, etc.) hand out a
    ``postgres://`` or ``postgresql://`` URL, but SQLAlchemy's async engine needs
    the ``postgresql+asyncpg://`` driver scheme. Rewrite it so DATABASE_URL can be
    pasted in verbatim."""
    if url.startswith("postgres://"):
        return "postgresql+asyncpg://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        return "postgresql+asyncpg://" + url[len("postgresql://"):]
    return url


def get_settings() -> Settings:
    return Settings(
        anthropic_api_key=os.environ.get("ANTHROPIC_API_KEY", ""),
        anthropic_model=os.environ.get("ANTHROPIC_MODEL", "claude-opus-4-8"),
        database_url=_normalize_db_url(
            os.environ.get("DATABASE_URL", "sqlite+aiosqlite:///./enhale.db")
        ),
        jwt_secret=os.environ.get("JWT_SECRET", "dev-insecure-change-me-32bytes-minimum!!"),
        jwt_algorithm=os.environ.get("JWT_ALGORITHM", "HS256"),
        jwt_expire_minutes=int(os.environ.get("JWT_EXPIRE_MINUTES", 60 * 24 * 7)),
    )
