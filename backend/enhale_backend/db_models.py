"""SQLAlchemy ORM tables.

The full parsed meal is stored as a JSON payload (Postgres JSONB / SQLite JSON),
with ``user_id`` and ``eaten_at`` pulled out as indexed columns so per-user,
per-day queries are cheap. This keeps the flexible LLM output schema-light while
still supporting the range queries the app needs.
"""

from __future__ import annotations

from datetime import date as date_type
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Date, DateTime, Float, ForeignKey, Integer, String, UniqueConstraint, func
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


class HealthWorkout(Base):
    """One workout session, keyed by the client's stable sample id (HealthKit
    UUID) so re-syncs are idempotent."""

    __tablename__ = "health_workouts"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    workout_type: Mapped[str] = mapped_column(String(64))
    start_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    end_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    duration_seconds: Mapped[float] = mapped_column(Float)
    active_energy_kcal: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    distance_meters: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    source: Mapped[Optional[str]] = mapped_column(String(128), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, server_default=func.now()
    )


class SleepNight(Base):
    """Nightly sleep summary — one row per user per night (upsert key)."""

    __tablename__ = "sleep_nights"
    __table_args__ = (UniqueConstraint("user_id", "date", name="uq_sleep_user_date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    date: Mapped[date_type] = mapped_column(Date, index=True)
    in_bed_seconds: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    asleep_seconds: Mapped[float] = mapped_column(Float)
    rem_seconds: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    deep_seconds: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    core_seconds: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    awake_seconds: Mapped[Optional[float]] = mapped_column(Float, nullable=True)


class DailyMetric(Base):
    """Per-day activity/vitals rollup — one row per user per day (upsert key)."""

    __tablename__ = "daily_metrics"
    __table_args__ = (UniqueConstraint("user_id", "date", name="uq_daily_user_date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    date: Mapped[date_type] = mapped_column(Date, index=True)
    steps: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    active_energy_kcal: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    resting_energy_kcal: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    resting_heart_rate: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    hrv_ms: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    body_mass_kg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)


class BloodWorkPanelRow(Base):
    """An uploaded lab report + its extracted markers (stored as JSON payload)."""

    __tablename__ = "bloodwork_panels"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    collected_on: Mapped[Optional[date_type]] = mapped_column(Date, nullable=True, index=True)
    source_filename: Mapped[str] = mapped_column(String(255))
    payload: Mapped[dict] = mapped_column(JSON)  # full BloodWorkPanel incl markers
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, server_default=func.now()
    )


class InsightReportRow(Base):
    """A generated recommendations report (stored as JSON payload)."""

    __tablename__ = "insight_reports"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    payload: Mapped[dict] = mapped_column(JSON)  # full InsightReport
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, server_default=func.now()
    )
