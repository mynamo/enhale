"""Anthropic-backed ``LLMClient`` using the official ``anthropic`` SDK.

The API key lives here, on the server — never in any client app. That's the
whole point of the backend service: iOS/web/Android call us, we call Claude.
"""

from __future__ import annotations

from anthropic import AsyncAnthropic


class AnthropicLLMClient:
    """Talks to Claude's Messages API via the official async SDK.

    Model default is ``claude-opus-4-8``. Meal parsing is a simple,
    frequently-run task, so ``claude-haiku-4-5`` is a much cheaper option worth
    trying — set ``ANTHROPIC_MODEL`` to switch without code changes.
    """

    def __init__(
        self,
        api_key: str,
        model: str = "claude-opus-4-8",
        max_tokens: int = 1024,
    ) -> None:
        self._client = AsyncAnthropic(api_key=api_key)
        self._model = model
        self._max_tokens = max_tokens

    async def complete(self, system: str, user: str) -> str:
        response = await self._client.messages.create(
            model=self._model,
            max_tokens=self._max_tokens,
            system=system,
            messages=[{"role": "user", "content": user}],
        )
        # Concatenate all text blocks; the parser extracts the JSON object.
        return "".join(
            block.text for block in response.content if block.type == "text"
        )
