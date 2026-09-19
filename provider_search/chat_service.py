"""Free-text request refinement for the conversational chat entry point.

Lets a client type something like "I need a plumber this weekend under $100"
instead of only tapping a fixed category. refine_request() extracts a
category (from the same 9-category taxonomy provider_search already
searches), an urgency bucket, a short notes summary, and — as of the
marketplace build plan's Phase 1A, task 3 — a job classification (size,
complexity, required skills/equipment/qualifications, estimated team size)
that feeds provider_search.models.ServiceRequest and, in Phase 1B, the
revived matching_engine scoring. Uses the Claude API when available, falling
back to keyword matching on any failure so this never raises (same pattern
as matching.matching_engine.ai_categorize).

Note: provider_search only filters by category + city (see
provider_search.services.search_providers) — there's no budget/schedule
filtering against Google Places, so a detail like "under $100" surfaces in
`notes` for the client to mention when they reach out, rather than actually
filtering results.
"""

import json
import logging
import os

try:
    import anthropic
except ImportError:
    anthropic = None

logger = logging.getLogger(__name__)

_CLAUDE_MODEL = "claude-sonnet-4-6"

URGENCY_CHOICES = ("today", "this_week", "exploring")
JOB_SIZE_CHOICES = ("small", "medium", "large")
JOB_COMPLEXITY_CHOICES = ("simple", "moderate", "complex")

# The classification's defaults when there isn't enough signal to do better
# (the keyword fallback path) — a blank/empty value, not a guess, so callers
# can tell "unclassified" apart from a real small/simple job.
_BLANK_CLASSIFICATION = {
    "job_size": "",
    "job_complexity": "",
    "required_skills": [],
    "estimated_team_size": None,
    "required_equipment": [],
    "required_qualifications": [],
}

# Mirrors matching.matching_engine.CATEGORY_DISPLAY_NAMES — kept as its own
# copy rather than imported so this module's prompt wording can evolve
# independently of the business-onboarding classifier.
_CATEGORY_DISPLAY_NAMES = {
    "plumbing": "Plumbing",
    "electrical": "Electrical",
    "carpentry": "Carpentry",
    "hvac": "HVAC (heating/cooling)",
    "painting": "Painting",
    "construction-finishing": "Construction/finishing",
    "drywall-decor": "Drywall and decor installation",
    "metalwork-aluminum": "Metalwork/aluminum work",
    "glass-mirrors": "Glass and mirrors",
}
_DISPLAY_NAME_TO_SLUG = {name: slug for slug, name in _CATEGORY_DISPLAY_NAMES.items()}

_URGENCY_KEYWORDS = {
    "today": ["today", "asap", "urgent", "emergency", "right now", "immediately", " now"],
    "this_week": ["this week", "few days", "weekend", "soon", "tomorrow"],
}


def _refine_with_llm(text: str) -> dict:
    """Raises on any failure so refine_request() can fall back to keywords."""
    if anthropic is None:
        raise RuntimeError("anthropic package is not installed")
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise RuntimeError("ANTHROPIC_API_KEY is not set")

    category_list = "\n".join(f"- {name}" for name in _CATEGORY_DISPLAY_NAMES.values())
    client = anthropic.Anthropic(api_key=api_key)
    response = client.with_options(timeout=10.0).messages.create(
        model=_CLAUDE_MODEL,
        max_tokens=400,
        system=(
            "You extract structured info from a home-service request written in free text. "
            "Reply with ONLY a JSON object (no markdown, no explanation) with exactly these keys:\n"
            '"category": one of the following, copied exactly as written:\n'
            f"{category_list}\n"
            '"urgency": one of "today", "this_week", or "exploring"\n'
            '"notes": a short (under 15 words) plain-English summary of what the person needs, '
            "written for a provider to read before making contact\n"
            '"job_size": one of "small", "medium", or "large" — your best estimate of the job\'s '
            "overall scale from the description alone\n"
            '"job_complexity": one of "simple", "moderate", or "complex"\n'
            '"required_skills": a short JSON array of specific skills the job needs (e.g. ["soldering", '
            '"drywall patching"]) — empty array if you can\'t tell\n'
            '"estimated_team_size": your best-guess integer number of workers the job likely needs (1 for '
            "anything a single professional could handle)\n"
            '"required_equipment": a short JSON array of equipment/tools the job likely needs — empty array '
            "if ordinary hand tools are enough or you can't tell\n"
            '"required_qualifications": a short JSON array of licenses/certifications the job likely needs '
            '(e.g. ["licensed electrician"]) — empty array if none stand out'
        ),
        messages=[{"role": "user", "content": text}],
    )

    reply = "".join(block.text for block in response.content if block.type == "text").strip()
    parsed = json.loads(reply)
    slug = _DISPLAY_NAME_TO_SLUG.get(parsed.get("category"))
    urgency = parsed.get("urgency")
    job_size = parsed.get("job_size")
    job_complexity = parsed.get("job_complexity")
    if slug is None or urgency not in URGENCY_CHOICES:
        raise ValueError(f"unrecognized structured reply from model: {parsed!r}")
    if job_size not in JOB_SIZE_CHOICES or job_complexity not in JOB_COMPLEXITY_CHOICES:
        raise ValueError(f"unrecognized job classification from model: {parsed!r}")

    team_size = parsed.get("estimated_team_size")
    team_size = int(team_size) if isinstance(team_size, (int, float)) and team_size > 0 else None

    def _string_list(value):
        return [str(item) for item in value] if isinstance(value, list) else []

    return {
        "category": slug,
        "urgency": urgency,
        "notes": str(parsed.get("notes", "")).strip(),
        "job_size": job_size,
        "job_complexity": job_complexity,
        "required_skills": _string_list(parsed.get("required_skills")),
        "estimated_team_size": team_size,
        "required_equipment": _string_list(parsed.get("required_equipment")),
        "required_qualifications": _string_list(parsed.get("required_qualifications")),
    }


def _refine_with_keywords(text: str) -> dict:
    from matching.matching_engine import ai_categorize

    categories = ai_categorize(text)
    category = next(iter(categories), None)

    text_lower = text.lower()
    urgency = "exploring"
    for level in ("today", "this_week"):
        if any(kw in text_lower for kw in _URGENCY_KEYWORDS[level]):
            urgency = level
            break

    return {
        "category": category,
        "urgency": urgency,
        "notes": text.strip()[:200],
        **_BLANK_CLASSIFICATION,
    }


def refine_request(text: str) -> dict:
    """Returns {"category": slug|None, "urgency": str, "notes": str,
    "job_size": str, "job_complexity": str, "required_skills": list,
    "estimated_team_size": int|None, "required_equipment": list,
    "required_qualifications": list}.

    `category` is None only when neither the AI call nor keyword matching
    could identify one of the 9 supported categories — callers should treat
    that as "ask the client to rephrase or pick a category manually" rather
    than guessing. The job-classification fields are blank/empty on the
    keyword-fallback path (see _BLANK_CLASSIFICATION) rather than guessed —
    keyword matching has no basis to estimate job size or team size.
    """
    try:
        return _refine_with_llm(text)
    except Exception:
        logger.warning("chat refine: Claude API call failed, falling back to keyword matching", exc_info=True)
        return _refine_with_keywords(text)
