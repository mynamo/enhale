"""Minimal LLM abstraction.

Keeping this a Protocol means ``MealParser`` never knows *which* model it talks
to: tests inject a canned-response stub, production injects the Anthropic-backed
client, and another provider could slot in later without touching the parser.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable


@runtime_checkable
class LLMClient(Protocol):
    async def complete(self, system: str, user: str) -> str:
        """Send a system + user prompt, return the raw assistant text.

        Implementations should request JSON output where possible; the caller is
        responsible for parsing it.
        """
        ...
