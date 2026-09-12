"""
Top Link AI — Matching Engine (prototype)

Core idea: two profile types (BUSINESS / INDIVIDUAL) submit a request,
the engine searches the profile database and returns ranked matches
with a transparent match percentage.

This is framework-agnostic today so it's testable standalone.
Drop it into Django as a service module (called from a DRF view) later —
no changes needed to the scoring logic itself.
"""

from dataclasses import dataclass, field
from datetime import datetime
from math import radians, sin, cos, sqrt, atan2
from typing import List, Optional


# ---------- Data model ----------

@dataclass
class Profile:
    id: str
    name: str
    role: str                      # "business" or "individual"
    categories: set                # e.g. {"plumbing", "emergency-repair"}
    lat: float
    lng: float
    available: bool = True
    rating: float = 0.0            # 0-5, optional, defaults to 0 if no reviews yet


@dataclass
class MatchRequest:
    requester_id: str
    categories: set                # what the requester is looking for
    lat: float
    lng: float
    max_distance_km: float = 25.0


@dataclass
class MatchResult:
    profile: Profile
    score: float                   # 0-100
    breakdown: dict                # transparency: why this score


# ---------- Scoring ----------

def _haversine_km(lat1, lng1, lat2, lng2) -> float:
    R = 6371.0
    dlat = radians(lat2 - lat1)
    dlng = radians(lng2 - lng1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng / 2) ** 2
    return R * 2 * atan2(sqrt(a), sqrt(1 - a))


def _category_score(req_categories: set, profile_categories: set) -> float:
    """Jaccard overlap between requested and offered categories, 0-1."""
    if not req_categories or not profile_categories:
        return 0.0
    intersection = req_categories & profile_categories
    union = req_categories | profile_categories
    return len(intersection) / len(union) if union else 0.0


def _distance_score(distance_km: float, max_distance_km: float) -> float:
    """Linear falloff: 1.0 at 0km, 0.0 at max_distance_km."""
    if distance_km >= max_distance_km:
        return 0.0
    return 1.0 - (distance_km / max_distance_km)


def _rating_score(rating: float) -> float:
    return rating / 5.0 if rating else 0.5  # neutral score if no reviews yet


# Weights — the actual product decision. These are placeholders;
# tune once you have real usage data or A/B results.
WEIGHTS = {
    "category": 0.55,
    "distance": 0.30,
    "rating": 0.15,
}


def find_matches(request: MatchRequest, candidates: List[Profile], top_n: int = 5) -> List[MatchResult]:
    results = []
    for p in candidates:
        if p.id == request.requester_id or not p.available:
            continue

        dist = _haversine_km(request.lat, request.lng, p.lat, p.lng)
        if dist > request.max_distance_km:
            continue

        cat_s = _category_score(request.categories, p.categories)
        dist_s = _distance_score(dist, request.max_distance_km)
        rating_s = _rating_score(p.rating)

        score = (
            cat_s * WEIGHTS["category"]
            + dist_s * WEIGHTS["distance"]
            + rating_s * WEIGHTS["rating"]
        ) * 100

        results.append(MatchResult(
            profile=p,
            score=round(score, 1),
            breakdown={
                "category_overlap": round(cat_s * 100, 1),
                "distance_km": round(dist, 1),
                "distance_score": round(dist_s * 100, 1),
                "rating_score": round(rating_s * 100, 1),
            }
        ))

    results.sort(key=lambda r: r.score, reverse=True)
    return results[:top_n]


# ---------- Demo ----------

if __name__ == "__main__":
    candidates = [
        Profile("p1", "Ahmed Plumbing Co.", "business", {"plumbing"}, 53.5461, -113.4938, rating=4.6),
        Profile("p2", "Sara's Electric", "business", {"electrical"}, 53.5501, -113.5001, rating=4.9),
        Profile("p3", "QuickFix Plumbers", "business", {"plumbing"}, 53.6000, -113.4500, rating=3.8),
        Profile("p4", "Karim (freelance plumber)", "individual", {"plumbing", "construction-finishing"}, 53.5480, -113.4900, rating=0.0),
        Profile("p5", "Far Away Plumbing", "business", {"plumbing"}, 53.9000, -113.9000, rating=4.2),
    ]

    request = MatchRequest(
        requester_id="client_1",
        categories={"plumbing"},
        lat=53.5444,
        lng=-113.4909,
        max_distance_km=25,
    )

    matches = find_matches(request, candidates)

    print(f"Request: looking for {request.categories}\n")
    for m in matches:
        print(f"{m.score:5.1f}%  {m.profile.name:28s} "
              f"(cat={m.breakdown['category_overlap']}%, "
              f"{m.breakdown['distance_km']}km, "
              f"rating_score={m.breakdown['rating_score']}%)")


# ---------- AI categorization layer ----------
# In production, replace `ai_categorize()` with a real call: send the free-text
# description to an LLM (or a fine-tuned classifier) with the fixed taxonomy list
# in the prompt, ask it to return the matching category ids. This stub uses
# keyword matching only to prove the pipeline shape — swap the implementation,
# not the interface, when you wire in the real model.

CATEGORY_TAXONOMY = {
    "plumbing": ["plumber", "plumbing", "pipe", "leak", "faucet", "drain", "sink", "toilet", "water heater"],
    "electrical": ["electric", "electrician", "wiring", "outlet", "breaker", "circuit", "fuse", "panel"],
    "carpentry": ["carpenter", "carpentry", "wood", "cabinet", "furniture", "framing", "deck"],
    "hvac": ["hvac", "heating", "cooling", "furnace", "air conditioning", "ac ", "ventilation", "duct"],
    "painting": ["paint", "painting", "painter", "wall finish", "exterior paint", "interior paint"],
    "construction-finishing": ["construction", "finishing", "contractor", "renovation", "remodel", "reno", "build"],
    "drywall-decor": ["drywall", "gypsum", "ceiling", "decor", "interior design", "molding"],
    "metalwork-aluminum": ["metalwork", "aluminum", "welding", "weld", "iron", "steel", "railing", "gate"],
    "glass-mirrors": ["glass", "mirror", "window", "glazing", "shower door"],
}


def ai_categorize(text: str) -> set:
    """Stand-in for an LLM/classifier call. Same input/output shape as production."""
    text_lower = text.lower()
    matched = set()
    for category, keywords in CATEGORY_TAXONOMY.items():
        if any(kw in text_lower for kw in keywords):
            matched.add(category)
    return matched


if __name__ == "__main__":
    print("\n--- AI categorization demo ---\n")

    business_description = "We're a plumber serving the Edmonton area, specializing in leaks, pipes, and faucet repair."
    client_request_text = "My kitchen sink is leaking and the faucet won't shut off."

    business_categories = ai_categorize(business_description)
    request_categories = ai_categorize(client_request_text)

    print(f"Business description: \"{business_description}\"")
    print(f"→ AI-assigned categories: {business_categories}\n")

    print(f"Client request: \"{client_request_text}\"")
    print(f"→ AI-assigned categories: {request_categories}\n")

    # feed straight into the existing scoring engine, unchanged
    ai_candidate = Profile("p6", "Ahmed Plumbing Co.", "business", business_categories, 53.5461, -113.4938, rating=4.6)
    ai_request = MatchRequest("client_2", request_categories, 53.5444, -113.4909, max_distance_km=25)

    for m in find_matches(ai_request, [ai_candidate]):
        print(f"{m.score:5.1f}%  {m.profile.name}  (cat_overlap={m.breakdown['category_overlap']}%)")
