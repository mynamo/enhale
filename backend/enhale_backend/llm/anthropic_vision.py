"""Anthropic-backed VisionClient — sends a PDF or image to Claude.

Claude reads PDFs (document block) and images (image block) natively, so we can
hand it a lab report and ask for structured JSON back.
"""

from __future__ import annotations

from anthropic import AsyncAnthropic


class AnthropicVisionClient:
    def __init__(
        self,
        api_key: str,
        model: str = "claude-opus-4-8",
        max_tokens: int = 4096,
    ) -> None:
        self._client = AsyncAnthropic(api_key=api_key)
        self._model = model
        self._max_tokens = max_tokens

    async def extract(
        self, system: str, user: str, media_type: str, data_b64: str
    ) -> str:
        if media_type == "application/pdf":
            file_block = {
                "type": "document",
                "source": {"type": "base64", "media_type": media_type, "data": data_b64},
            }
        else:  # image/png, image/jpeg, ...
            file_block = {
                "type": "image",
                "source": {"type": "base64", "media_type": media_type, "data": data_b64},
            }

        response = await self._client.messages.create(
            model=self._model,
            max_tokens=self._max_tokens,
            system=system,
            messages=[{"role": "user", "content": [file_block, {"type": "text", "text": user}]}],
        )
        return "".join(b.text for b in response.content if b.type == "text")
