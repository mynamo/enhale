"""Abstraction over a multimodal LLM that can read a document/image file.

Separate from the text-only ``LLMClient`` so meal parsing stays simple. Tests
inject a stub returning canned JSON; production uses the Anthropic-backed impl.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable


@runtime_checkable
class VisionClient(Protocol):
    async def extract(
        self, system: str, user: str, media_type: str, data_b64: str
    ) -> str:
        """Send a file (base64) + prompts, return the raw assistant text.

        ``media_type`` is e.g. ``application/pdf`` or ``image/png``.
        """
        ...
