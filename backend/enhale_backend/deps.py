"""Shared FastAPI dependencies not tied to a single router."""

from __future__ import annotations

from fastapi import Depends, HTTPException

from .config import Settings, get_settings
from .llm.anthropic_client import AnthropicLLMClient
from .parsing.meal_parser import MealParser


def get_parser(settings: Settings = Depends(get_settings)) -> MealParser:
    """Build a parser wired to the real LLM.

    Overridable in tests via ``app.dependency_overrides[get_parser]`` so no
    network or API key is needed to exercise the routes.
    """
    if not settings.anthropic_api_key:
        raise HTTPException(status_code=500, detail="ANTHROPIC_API_KEY is not set")
    client = AnthropicLLMClient(
        api_key=settings.anthropic_api_key,
        model=settings.anthropic_model,
    )
    return MealParser(client)
