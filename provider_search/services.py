"""Real service-provider lookup via the Google Places API (New).

Results are cached per (category, city) through Django's cache framework —
Places API calls cost money per request, and this data (business listings)
doesn't change fast enough to justify looking it up on every search.
"""

import logging
import os

import requests
from django.core.cache import cache

logger = logging.getLogger(__name__)

GOOGLE_PLACES_API_KEY = os.environ.get("GOOGLE_PLACES_API_KEY")

_PLACES_SEARCH_URL = "https://places.googleapis.com/v1/places:searchText"

# Comma-separated field paths — Places API (New) charges more for larger
# field masks, so this only requests what search_providers() actually returns.
_FIELD_MASK = ",".join([
    "places.id",
    "places.displayName",
    "places.formattedAddress",
    "places.internationalPhoneNumber",
    "places.websiteUri",
    "places.rating",
    "places.userRatingCount",
    "places.googleMapsUri",
])

CACHE_TTL_SECONDS = 35 * 24 * 60 * 60  # 35 days

# Service categories this app supports — keys match the slugs used
# elsewhere (see matching.matching_engine.CATEGORY_TAXONOMY), values are the
# English search phrase sent to Places.
CATEGORY_QUERIES = {
    "plumbing": "plumber",
    "electrical": "electrician",
    "carpentry": "carpenter",
    "hvac": "HVAC contractor",
    "painting": "painting contractor",
    "construction-finishing": "general contractor",
    "drywall-decor": "drywall contractor",
    "metalwork-aluminum": "metal fabrication welding shop",
    "glass-mirrors": "glass and mirror shop",
}

CITIES = ["Edmonton", "Calgary", "Fort McMurray", "Red Deer"]


def _cache_key(category: str, city: str) -> str:
    return f"provider_search:{category}:{city}".lower().replace(" ", "_")


def search_providers(category: str, city: str, max_results: int = 10, force_refresh: bool = False) -> list[dict]:
    """Return up to `max_results` real providers for `category` in `city`.

    Cached for CACHE_TTL_SECONDS unless `force_refresh` is True (used by the
    `refresh_provider_data` management command). Raises ValueError for an
    unknown category/city, and RuntimeError if the API key isn't configured
    — callers decide how to turn that into an HTTP response.
    """
    if category not in CATEGORY_QUERIES:
        raise ValueError(f"Unknown category: {category!r}. Must be one of {list(CATEGORY_QUERIES)}.")
    if city not in CITIES:
        raise ValueError(f"Unknown city: {city!r}. Must be one of {CITIES}.")

    cache_key = _cache_key(category, city)
    if not force_refresh:
        cached = cache.get(cache_key)
        if cached is not None:
            return cached[:max_results]

    if not GOOGLE_PLACES_API_KEY:
        raise RuntimeError("GOOGLE_PLACES_API_KEY is not set.")

    text_query = f"{CATEGORY_QUERIES[category]} in {city}, Alberta, Canada"

    response = requests.post(
        _PLACES_SEARCH_URL,
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": GOOGLE_PLACES_API_KEY,
            "X-Goog-FieldMask": _FIELD_MASK,
        },
        json={"textQuery": text_query, "maxResultCount": max_results},
        timeout=10,
    )
    response.raise_for_status()
    payload = response.json()

    results = [
        {
            "place_id": place.get("id"),
            "name": place.get("displayName", {}).get("text", ""),
            "address": place.get("formattedAddress", ""),
            "phone": place.get("internationalPhoneNumber", ""),
            "website": place.get("websiteUri", ""),
            "rating": place.get("rating"),
            "rating_count": place.get("userRatingCount"),
            "maps_url": place.get("googleMapsUri", ""),
        }
        for place in payload.get("places", [])
    ]

    cache.set(cache_key, results, CACHE_TTL_SECONDS)
    return results[:max_results]
