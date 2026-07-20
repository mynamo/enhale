"""SQLAlchemy ORM tables.

The full parsed meal is stored as a JSON payload (Postgres JSONB / SQLite JSON),
with ``user_id`` and ``eaten_at`` pulled out as indexed columns so per-user,
per-day queries are cheap. This keeps the flexible LLM output schema-light while
still supporting the range queries the app needs.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import JSON

from .db import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, server_default=func.now()
    )

    meals: Mapped[list["Meal"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class Meal(Base):
    __tablename__ = "meals"

    # ParsedMeal.id (UUID) as the primary key, stored as text.
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    eaten_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    # The full ParsedMeal, serialized (items, meal_type, confidence, ...).
    payload: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, server_default=func.now()
    )

    user: Mapped["User"] = relationship(back_populates="meals")
