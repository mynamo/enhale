"""Per-user meal routes: parse+store, list by day, delete.

Every route is scoped to the authenticated user — a user can only ever see or
touch their own meals (health data isolation).
"""

from __future__ import annotations

from datetime import date, datetime, time, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..auth.dependencies import get_current_user
from ..db import get_session
from ..db_models import Meal, User
from ..deps import get_parser
from ..models import FoodItem, MealType, ParsedMeal
from ..parsing.meal_parser import MalformedResponseError, MealParser, NoFoodFoundError

router = APIRouter(prefix="/meals", tags=["meals"])


class ParseMealRequest(BaseModel):
    transcript: str
    now: Optional[datetime] = None
    timezone: str = "UTC"


@router.post("/parse", response_model=ParsedMeal)
async def parse_and_store(
    body: ParseMealRequest,
    user: User = Depends(get_current_user),
    parser: MealParser = Depends(get_parser),
    session: AsyncSession = Depends(get_session),
) -> ParsedMeal:
    try:
        meal = await parser.parse(
            transcript=body.transcript, now=body.now, tz_name=body.timezone
        )
    except NoFoodFoundError as exc:
        raise HTTPException(status_code=422, detail="No food found in transcript") from exc
    except MalformedResponseError as exc:
        raise HTTPException(status_code=502, detail="LLM returned an unparseable response") from exc

    session.add(
        Meal(
            id=str(meal.id),
            user_id=user.id,
            eaten_at=meal.eaten_at,
            payload=meal.model_dump(mode="json"),
        )
    )
    await session.commit()
    return meal


@router.get("", response_model=list[ParsedMeal])
async def list_meals(
    on: Optional[date] = None,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[ParsedMeal]:
    """List the user's meals, newest first. Pass ``?on=YYYY-MM-DD`` for one day."""
    stmt = select(Meal).where(Meal.user_id == user.id)
    if on is not None:
        start = datetime.combine(on, time.min, tzinfo=timezone.utc)
        end = datetime.combine(on, time.max, tzinfo=timezone.utc)
        stmt = stmt.where(Meal.eaten_at >= start, Meal.eaten_at <= end)
    stmt = stmt.order_by(Meal.eaten_at.desc())

    rows = (await session.scalars(stmt)).all()
    return [ParsedMeal.model_validate(row.payload) for row in rows]


class UpdateFoodItem(BaseModel):
    """One edited item. ``id`` matches an existing item so its non-editable
    fields (micronutrients) are preserved; omit it for a newly added item."""
    id: Optional[UUID] = None
    name: str
    quantity: Optional[str] = None
    calories: Optional[float] = None
    protein_grams: Optional[float] = None
    carb_grams: Optional[float] = None
    fat_grams: Optional[float] = None


class UpdateMealRequest(BaseModel):
    meal_type: MealType
    eaten_at: datetime
    items: list[UpdateFoodItem]


@router.put("/{meal_id}", response_model=ParsedMeal)
async def update_meal(
    meal_id: str,
    body: UpdateMealRequest,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ParsedMeal:
    """Edit a stored meal. Merges the editable fields into the existing payload
    so nutrition detail the client doesn't send (micronutrients) is retained for
    items kept by id; items dropped from the list are removed."""
    row = await session.get(Meal, meal_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Meal not found")

    meal = ParsedMeal.model_validate(row.payload)
    existing = {str(item.id): item for item in meal.items}

    new_items: list[FoodItem] = []
    for edited in body.items:
        base = existing.get(str(edited.id)) if edited.id is not None else None
        if base is not None:
            base.name = edited.name
            base.quantity = edited.quantity
            base.calories = edited.calories
            base.protein_grams = edited.protein_grams
            base.carb_grams = edited.carb_grams
            base.fat_grams = edited.fat_grams
            new_items.append(base)
        else:
            new_items.append(
                FoodItem(
                    name=edited.name,
                    quantity=edited.quantity,
                    calories=edited.calories,
                    protein_grams=edited.protein_grams,
                    carb_grams=edited.carb_grams,
                    fat_grams=edited.fat_grams,
                    estimated=False,  # user-entered, not an LLM estimate
                )
            )

    meal.items = new_items
    meal.meal_type = body.meal_type
    meal.eaten_at = body.eaten_at

    row.eaten_at = body.eaten_at
    row.payload = meal.model_dump(mode="json")
    await session.commit()
    return meal


@router.delete("/{meal_id}", status_code=204)
async def delete_meal(
    meal_id: str,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    meal = await session.get(Meal, meal_id)
    if meal is None or meal.user_id != user.id:
        # Same 404 whether it doesn't exist or isn't yours — don't leak existence.
        raise HTTPException(status_code=404, detail="Meal not found")
    await session.delete(meal)
    await session.commit()
