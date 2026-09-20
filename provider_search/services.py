"""Real service-provider lookup via the Google Places API (New).

Results are cached per (category, city) through Django's cache framework —
Places API calls cost money per request, and this data (business listings)
doesn't change fast enough to justify looking it up on every search.
"""

import hashlib
import logging
import os
from datetime import timedelta

import requests
from django.core.cache import cache
from django.db.models import Count
from django.utils import timezone

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
# elsewhere (see matching.matching_engine.CATEGORY_TAXONOMY and, as of Phase
# 1B, catalog.Service.slug — this dict is seeded from the same
# google_places_query values as the catalog migration, kept as its own copy
# so an admin editing a Service's query phrase later doesn't silently change
# Places search behavior without a code review). Values are the English
# search phrase sent to Places.
CATEGORY_QUERIES = {
    "plumbing": "plumber",
    "electrical": "electrician",
    "carpentry": "carpenter",
    "hvac": "HVAC contractor",
    "painting": "painting contractor",
    "general-maintenance": "handyman service",
    "construction-finishing": "general contractor",
    "drywall-decor": "drywall contractor",
    "metalwork-aluminum": "metal fabrication welding shop",
    "glass-mirrors": "glass and mirror shop",
    "cleaning-services": "house cleaning service",
    "moving-services": "moving company",
    "furniture-assembly": "furniture assembly service",
    "home-repair": "home repair service",
    "mechanic-services": "auto mechanic",
    "car-wash": "car wash",
    "tire-repair": "tire shop",
    "towing-services": "towing service",
    "accounting-services": "accounting firm",
    "marketing-services": "marketing agency",
    "website-design": "web design agency",
    "it-services": "IT services company",
    "photography": "photographer",
    "event-decoration": "event decorator",
    "event-planning": "event planner",
    "sound-lighting": "event sound and lighting rental",
    "barber-services": "barber shop",
    "beauty-services": "beauty salon",
    "personal-training": "personal trainer",
    "tutoring": "tutoring service",
    "flooring": "flooring contractor",
    "roofing": "roofing contractor",
    "concrete-work": "concrete contractor",
    "kitchen-renovation": "kitchen renovation contractor",
    "bathroom-renovation": "bathroom renovation contractor",
    "delivery-services": "courier delivery service",
    "storage-services": "self storage",
    "legal-services": "law firm",
    "catering": "catering service",
    "security-services": "security guard company",
    "lawn-care": "lawn care service",
    "snow-removal": "snow removal service",
    "tree-services": "tree service",
    "landscaping": "landscaping company",
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


RECENT_ENGAGEMENT_WINDOW = timedelta(days=7)


def recent_contact_counts(place_ids: list[str]) -> dict[str, int]:
    """Social proof: for each place_id, how many distinct devices have set
    their ProviderMatch status to "contacted" or further within the last
    week. Imported here (not at module level) to avoid a circular import —
    provider_search.models doesn't import this module, but keeping the
    import local mirrors how chat_service.py reaches into matching.matching_engine.
    """
    from .models import ProviderMatch

    if not place_ids:
        return {}
    cutoff = timezone.now() - RECENT_ENGAGEMENT_WINDOW
    rows = (
        ProviderMatch.objects.filter(
            place_id__in=place_ids,
            status__in=[ProviderMatch.STATUS_CONTACTED, ProviderMatch.STATUS_COMPLETED],
            last_viewed_at__gte=cutoff,
        )
        .values("place_id")
        .annotate(count=Count("device_id", distinct=True))
    )
    return {row["place_id"]: row["count"] for row in rows}


def estimated_response_minutes(place_id: str) -> int:
    """Placeholder "usually responds within N min" estimate, shown only
    after a client unlocks a provider's contact info. There's no real
    messaging/response-time tracking in this app yet, so this derives a
    stable-per-provider value (5-55 min) from a hash of place_id rather than
    inventing fake historical data that looks like it came from real
    measurements — same value every time for the same provider, but not
    based on anything real. Replace with a real calculation once actual
    contact/response events are tracked.
    """
    digest = hashlib.md5(place_id.encode()).hexdigest()
    return 5 + (int(digest[:8], 16) % 51)


def availability_map(place_ids: list[str]) -> dict[str, bool]:
    """This platform's own available-now/busy override per place_id (see
    ProviderAvailability). A place_id with no row is treated as available.
    """
    from .models import ProviderAvailability

    if not place_ids:
        return {}
    rows = ProviderAvailability.objects.filter(place_id__in=place_ids).values("place_id", "is_available_now")
    return {row["place_id"]: row["is_available_now"] for row in rows}
