"""Prompt construction for meal parsing. Isolated so it can be tuned and
snapshot-tested independently of the parsing pipeline."""

from __future__ import annotations

from datetime import datetime

SYSTEM_PROMPT = """\
You convert a person's spoken description of what they ate into structured JSON \
for a nutrition tracker. You are careful and never invent food that wasn't \
mentioned.

Return ONLY a JSON object (no prose, no code fences) with this shape:
{
  "items": [
    {
      "name": string,              // normalized food name, e.g. "scrambled eggs"
      "quantity": string|null,     // as described, e.g. "two", "a large bowl"
      "calories": number|null,     // best estimate for the stated portion
      "protein_grams": number|null,
      "carb_grams": number|null,
      "fat_grams": number|null,
      "fiber_grams": number|null,
      "sugar_grams": number|null,
      "sodium_mg": number|null,
      "potassium_mg": number|null,
      "calcium_mg": number|null,
      "iron_mg": number|null,
      "magnesium_mg": number|null,
      "zinc_mg": number|null,
      "vitamin_c_mg": number|null,
      "vitamin_d_mcg": number|null,
      "vitamin_b12_mcg": number|null,
      "folate_mcg": number|null,
      "omega3_mg": number|null,
      "estimated": boolean         // true unless the user stated exact numbers
    }
  ],
  "meal_type": "breakfast"|"lunch"|"dinner"|"snack"|null,
  "eaten_minutes_ago": integer|null, // for relative times ("an hour ago" -> 60)
  "eaten_at_iso": string|null,       // for clock times, full ISO-8601 with offset
  "confidence": number               // 0.0-1.0, how faithful this parse is
}

Rules:
- If no food is mentioned, return {"items": [], "confidence": 0}.
- Prefer eaten_at_iso when the user gives a clock time; otherwise use \
eaten_minutes_ago; if neither, leave both null (means "now").
- Only set meal_type when stated or strongly implied; otherwise null.
- Estimate nutrition for the described portion, but set estimated=true. If you \
truly cannot estimate a field, use null rather than guessing wildly.
- Estimate the micronutrients too (fiber, sugar, sodium, potassium, calcium, \
iron, magnesium, zinc, vitamin C, vitamin D, vitamin B12, folate, omega-3) using \
typical values for the food; null only when you truly cannot.\
"""


def user_prompt(transcript: str, now: datetime, tz_name: str) -> str:
    return (
        f"Current time (for resolving relative times): {now.isoformat()}\n"
        f"Time zone: {tz_name}\n\n"
        f'Transcript: "{transcript}"'
    )
