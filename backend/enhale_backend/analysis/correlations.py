"""Deterministic analysis over the user's data.

Rather than asking the LLM to eyeball raw logs, we compute the objective
findings here — meal timing around workouts, late-night eating, trends,
correlations, lab trajectories, average daily nutrients — and feed those to the
LLM as evidence. Makes insights more rigorous and less hand-wavy.

Every function guards for sparse data and simply omits a finding when there
isn't enough to say something honest.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from statistics import mean
from typing import Optional

from ..bloodwork_models import BloodWorkPanel
from ..health_models import HealthSummary
from ..models import ParsedMeal

# Rough adult reference intakes (RDA/AI); used only to note apparent shortfalls,
# with the caveat that meal logging is often incomplete.
_RDA = {
    "fiber_grams": 28, "potassium_mg": 3400, "calcium_mg": 1000, "iron_mg": 14,
    "magnesium_mg": 400, "zinc_mg": 11, "vitamin_c_mg": 90, "vitamin_d_mcg": 20,
    "vitamin_b12_mcg": 2.4, "folate_mcg": 400, "omega3_mg": 250,
}
_MICRO_LABELS = {
    "fiber_grams": ("fiber", "g"), "potassium_mg": ("potassium", "mg"),
    "calcium_mg": ("calcium", "mg"), "iron_mg": ("iron", "mg"),
    "magnesium_mg": ("magnesium", "mg"), "zinc_mg": ("zinc", "mg"),
    "vitamin_c_mg": ("vitamin C", "mg"), "vitamin_d_mcg": ("vitamin D", "mcg"),
    "vitamin_b12_mcg": ("vitamin B12", "mcg"), "folate_mcg": ("folate", "mcg"),
    "omega3_mg": ("omega-3", "mg"),
}


def _utc(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def compute_findings(
    meals: list[ParsedMeal],
    health: HealthSummary,
    panels: list[BloodWorkPanel],
) -> list[str]:
    findings: list[str] = []
    findings += _meal_timing(meals)
    findings += _workout_meal_windows(meals, health)
    findings += _daily_nutrients(meals)
    findings += _sleep(health)
    findings += _activity(health)
    findings += _sleep_vs_resting_hr(health)
    findings += _lab_trajectory(panels)
    return findings


def _days_span(meals: list[ParsedMeal]) -> int:
    if not meals:
        return 0
    days = {_utc(m.eaten_at).date() for m in meals}
    return max(1, len(days))


def _meal_timing(meals: list[ParsedMeal]) -> list[str]:
    if len(meals) < 3:
        return []
    late = [m for m in meals if _utc(m.eaten_at).hour >= 21 or _utc(m.eaten_at).hour < 4]
    pct = round(100 * len(late) / len(meals))
    if pct >= 25:
        return [f"{pct}% of logged meals ({len(late)}/{len(meals)}) were late-night (after 9pm / before 4am)."]
    return []


def _workout_meal_windows(meals: list[ParsedMeal], health: HealthSummary) -> list[str]:
    if not health.workouts or not meals:
        return []
    pre_gaps, post_gaps = [], []
    for w in health.workouts:
        start = _utc(w.start_at)
        end = _utc(w.end_at)
        for m in meals:
            t = _utc(m.eaten_at)
            if 0 < (start - t).total_seconds() <= 3 * 3600:
                pre_gaps.append((start - t).total_seconds() / 60)
            if 0 < (t - end).total_seconds() <= 3 * 3600:
                post_gaps.append((t - end).total_seconds() / 60)
    out = []
    if pre_gaps:
        out.append(f"Ate within 3h before a workout {len(pre_gaps)} time(s), avg {round(mean(pre_gaps))} min prior.")
    else:
        out.append("No meals logged within 3h before any workout (possible fasted training).")
    if post_gaps:
        out.append(f"Ate within 3h after a workout {len(post_gaps)} time(s), avg {round(mean(post_gaps))} min after (recovery window).")
    else:
        out.append("No meals logged within 3h after any workout (possible missed recovery nutrition).")
    return out


def _daily_nutrients(meals: list[ParsedMeal]) -> list[str]:
    if not meals:
        return []
    days = _days_span(meals)
    cals = sum(m.total_calories for m in meals)
    prot = sum(i.protein_grams or 0 for m in meals for i in m.items)
    out = [f"Averaged ~{round(cals / days)} kcal and ~{round(prot / days)} g protein per logged day ({days} day(s), may be incomplete)."]

    # Average daily micro intake + apparent shortfalls
    totals: dict[str, float] = defaultdict(float)
    present: set[str] = set()
    for m in meals:
        for i in m.items:
            for key in _MICRO_LABELS:
                v = getattr(i, key, None)
                if v is not None:
                    totals[key] += v
                    present.add(key)
    low = []
    for key in present:
        daily = totals[key] / days
        rda = _RDA.get(key)
        if rda and daily < 0.5 * rda:
            label, unit = _MICRO_LABELS[key]
            low.append(f"{label} (~{round(daily)}{unit}/day vs ~{rda}{unit} target)")
    if low:
        out.append("Nutrients that look low in logged food (logging may be incomplete): " + "; ".join(low) + ".")
    return out


def _sleep(health: HealthSummary) -> list[str]:
    nights = [s.asleep_seconds / 3600 for s in health.sleep if s.asleep_seconds]
    if len(nights) < 3:
        return []
    avg = mean(nights)
    out = [f"Averaged {avg:.1f}h of sleep over {len(nights)} nights."]
    if len(nights) >= 6:
        recent = mean(nights[: len(nights) // 2])
        earlier = mean(nights[len(nights) // 2 :])
        if abs(recent - earlier) >= 0.5:
            direction = "less" if recent < earlier else "more"
            out.append(f"Recent sleep is trending {direction} ({recent:.1f}h vs {earlier:.1f}h earlier).")
    return out


def _activity(health: HealthSummary) -> list[str]:
    steps = [d.steps for d in health.daily if d.steps is not None]
    hr = [d.resting_heart_rate for d in health.daily if d.resting_heart_rate is not None]
    out = []
    if steps:
        out.append(f"Averaged {round(mean(steps))} steps/day over {len(steps)} days.")
    if hr:
        out.append(f"Resting heart rate averaged {round(mean(hr))} bpm.")
    return out


def _sleep_vs_resting_hr(health: HealthSummary) -> list[str]:
    # Pair each night's sleep with the next day's resting HR.
    sleep_by_day = {s.date: s.asleep_seconds / 3600 for s in health.sleep if s.asleep_seconds}
    hr_by_day = {d.date: d.resting_heart_rate for d in health.daily if d.resting_heart_rate is not None}
    pairs = [(sleep_by_day[day], hr_by_day[day]) for day in sleep_by_day if day in hr_by_day]
    if len(pairs) < 5:
        return []
    r = _pearson([p[0] for p in pairs], [p[1] for p in pairs])
    if r is None or abs(r) < 0.4:
        return []
    rel = "less sleep tends to coincide with higher resting HR" if r < 0 else "more sleep coincides with higher resting HR"
    return [f"Across {len(pairs)} days, sleep and resting heart rate correlate (r={r:.2f}): {rel}."]


def _lab_trajectory(panels: list[BloodWorkPanel]) -> list[str]:
    if len(panels) < 2:
        return []
    # panels are newest-first; compare each marker's newest vs oldest numeric value.
    by_name: dict[str, list[tuple[Optional[str], float]]] = defaultdict(list)
    for p in sorted(panels, key=lambda x: (x.collected_on or "")):
        for mk in p.markers:
            if mk.value_num is not None:
                by_name[mk.name].append((str(p.collected_on), mk.value_num))
    out = []
    for name, series in by_name.items():
        if len(series) >= 2 and series[0][1] != 0:
            first, last = series[0][1], series[-1][1]
            change = round(100 * (last - first) / abs(series[0][1]))
            if abs(change) >= 10:
                direction = "up" if last > first else "down"
                out.append(f"{name} trending {direction}: {first} → {last} ({change:+d}%).")
    return out


def _pearson(xs: list[float], ys: list[float]) -> Optional[float]:
    n = len(xs)
    if n < 2:
        return None
    mx, my = mean(xs), mean(ys)
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    dx = sum((x - mx) ** 2 for x in xs) ** 0.5
    dy = sum((y - my) ** 2 for y in ys) ** 0.5
    if dx == 0 or dy == 0:
        return None
    return num / (dx * dy)
