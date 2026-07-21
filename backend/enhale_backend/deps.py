"""Shared FastAPI dependencies not tied to a single router."""

from __future__ import annotations

from fastapi import Depends, HTTPException

from .bloodwork.extractor import BloodWorkExtractor
from .config import Settings, get_settings
from .llm.anthropic_client import AnthropicLLMClient
from .llm.anthropic_vision import AnthropicVisionClient
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


def get_bloodwork_extractor(
    settings: Settings = Depends(get_settings),
) -> BloodWorkExtractor:
    """Build the blood-work extractor wired to Claude's vision/document input.

    Overridable in tests via ``app.dependency_overrides[get_bloodwork_extractor]``.
    """
    if not settings.anthropic_api_key:
        raise HTTPException(status_code=500, detail="ANTHROPIC_API_KEY is not set")
    client = AnthropicVisionClient(
        api_key=settings.anthropic_api_key,
        model=settings.anthropic_model,
    )
    return BloodWorkExtractor(client)
