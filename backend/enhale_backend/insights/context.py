"""Turn the user's structured data into a compact text summary for the LLM."""

from __future__ import annotations

from typing import Optional

from ..bloodwork_models import BloodWorkPanel
from ..health_models import HealthSummary
from ..models import ParsedMeal
from ..profile_models import SymptomLog, UserProfile


def build_context(
    meals: list[ParsedMeal],
    health: HealthSummary,
    panels: list[BloodWorkPanel],
    profile: Optional[UserProfile] = None,
    symptoms: Optional[list[SymptomLog]] = None,
    findings: Optional[list[str]] = None,
) -> str:
    sections: list[str] = []

    # Profile (confounders matter — meds, supplements, smoking, family history)
    if profile is not None:
        p = []
        from datetime import date as _date
        if profile.birth_year:
            p.append(f"age ~{_date.today().year - profile.birth_year}")
        if profile.sex:
            p.append(profile.sex)
        if profile.height_cm:
            p.append(f"{profile.height_cm:.0f} cm")
        if profile.ethnicity:
            p.append(profile.ethnicity)
        if profile.smoking:
            p.append(f"smoking: {profile.smoking}")
        if profile.alcohol:
            p.append(f"alcohol: {profile.alcohol}")
        if profile.medications:
            p.append("meds: " + ", ".join(profile.medications))
        if profile.supplements:
            p.append("supplements: " + ", ".join(profile.supplements))
        if profile.conditions:
            p.append("conditions: " + ", ".join(profile.conditions))
        if profile.family_history:
            p.append(f"family history: {profile.family_history}")
        if p:
            sections.append("PROFILE: " + "; ".join(p))

    # Reported symptoms / concerns
    if symptoms:
        lines = []
        for s in symptoms:
            extra = []
            if s.onset:
                extra.append(f"since {s.onset}")
            if s.severity:
                extra.append(f"severity {s.severity}/5")
            if s.notes:
                extra.append(s.notes)
            lines.append(f"- {s.name}" + (f" ({', '.join(extra)})" if extra else ""))
        sections.append("REPORTED SYMPTOMS:\n" + "\n".join(lines))

    # Computed findings first — the objective evidence
    if findings:
        sections.append("COMPUTED FINDINGS (deterministic analysis):\n" + "\n".join(f"- {f}" for f in findings))

    # Meals
    if meals:
        lines = []
        for m in sorted(meals, key=lambda x: x.eaten_at, reverse=True):
            items = ", ".join(i.name for i in m.items)
            kcal = int(m.total_calories)
            when = m.eaten_at.strftime("%Y-%m-%d %H:%M")
            lines.append(f"- {when} {m.meal_type.value}: {items}" + (f" (~{kcal} kcal)" if kcal else ""))
        sections.append("MEALS (most recent first):\n" + "\n".join(lines))
    else:
        sections.append("MEALS: none logged.")

    # Daily activity
    if health.daily:
        lines = []
        for d in health.daily:
            parts = []
            if d.steps is not None:
                parts.append(f"{d.steps} steps")
            if d.active_energy_kcal is not None:
                parts.append(f"{int(d.active_energy_kcal)} active kcal")
            if d.resting_heart_rate is not None:
                parts.append(f"{int(d.resting_heart_rate)} bpm resting")
            if d.hrv_ms is not None:
                parts.append(f"HRV {int(d.hrv_ms)} ms")
            if d.body_mass_kg is not None:
                parts.append(f"{d.body_mass_kg:.1f} kg")
            lines.append(f"- {d.date}: " + ", ".join(parts))
        sections.append("DAILY ACTIVITY:\n" + "\n".join(lines))

    # Sleep
    if health.sleep:
        lines = [f"- {s.date}: {s.asleep_seconds / 3600:.1f}h asleep" for s in health.sleep]
        sections.append("SLEEP:\n" + "\n".join(lines))

    # Workouts
    if health.workouts:
        lines = []
        for w in health.workouts:
            kcal = f", {int(w.active_energy_kcal)} kcal" if w.active_energy_kcal else ""
            lines.append(f"- {w.start_at.strftime('%Y-%m-%d')} {w.workout_type} {int(w.duration_seconds / 60)}min{kcal}")
        sections.append("WORKOUTS:\n" + "\n".join(lines))

    # Blood work (emphasize flagged values)
    if panels:
        lines = []
        for p in panels:
            header = f"Panel {p.collected_on or 'undated'} ({p.source_filename}):"
            marker_lines = []
            for mk in p.markers:
                flag = f" [{mk.flag.upper()}]" if mk.flag in ("high", "low") else ""
                ref = f" (ref {mk.reference_range})" if mk.reference_range else ""
                unit = f" {mk.unit}" if mk.unit else ""
                marker_lines.append(f"    {mk.name}: {mk.value}{unit}{ref}{flag}")
            lines.append(header + "\n" + "\n".join(marker_lines))
        sections.append("BLOOD WORK:\n" + "\n".join(lines))

    return "\n\n".join(sections)
