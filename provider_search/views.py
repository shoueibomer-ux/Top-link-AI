import requests
from django.utils import timezone
from rest_framework.views import APIView
from rest_framework.response import Response

from matching.models import Subscription
from .chat_service import refine_request
from .models import ProviderAvailability, ProviderMatch, ProviderOnboarding, ServiceRequest
from .serializers import ProviderMatchSerializer, ProviderOnboardingSerializer, RealProviderSerializer
from .services import (
    CATEGORY_QUERIES,
    CITIES,
    availability_map,
    estimated_response_minutes,
    recent_contact_counts,
    search_providers,
)

UNLOCK_PRICE_USD = "4.99"


def _is_subscribed(device_id: str) -> bool:
    subscription = Subscription.objects.filter(device_id=device_id).first()
    if subscription is None or subscription.status not in ("trial", "active"):
        return False
    if subscription.expiry_date and subscription.expiry_date < timezone.now():
        return False
    return True


def _enrich(providers: list[dict], city: str) -> None:
    """Attaches the fields every provider gets regardless of unlock state —
    city, social proof, availability, and the response-time estimate — in
    place, on the raw search_providers() dicts."""
    place_ids = [provider["place_id"] for provider in providers if provider["place_id"]]
    contact_counts = recent_contact_counts(place_ids)
    availability = availability_map(place_ids)
    for provider in providers:
        provider["city"] = city
        provider["recent_contact_count"] = contact_counts.get(provider["place_id"], 0)
        provider["is_available_now"] = availability.get(provider["place_id"], True)
        provider["estimated_response_minutes"] = (
            estimated_response_minutes(provider["place_id"]) if provider["place_id"] else None
        )


def _search_and_record(
    category: str,
    city: str,
    device_id: str,
    force_refresh: bool = False,
    problem_description: str = "",
    classification: dict | None = None,
) -> dict:
    """Shared by ProviderSearchView and ChatRefineView: search Google Places
    for `category`/`city`, then serialize every result through
    RealProviderSerializer, which masks the phone and omits address/website/
    maps_url for any place_id this device hasn't unlocked yet (see
    ProviderUnlockView — that is the ONLY place a ProviderMatch row, and
    therefore a device's unlock of a specific provider, gets created).
    Appearing in these results never creates one. Returns the dict to use
    directly as a Response body, or raises RuntimeError/requests.RequestException
    same as search_providers.

    `problem_description` is only ever non-blank when called from the chat
    flow (see ChatRefineView) — the fixed category-tap flow has no free text
    to record, so it's left blank there rather than fabricated. Likewise
    `classification` (job_size/job_complexity/etc., from
    chat_service.refine_request) is only ever populated from chat.

    Build plan Phase 1A, task 4: every call creates a ServiceRequest — the
    "job" anchor Phase 1B's matching and Phase 1C's Leads read from — even
    when no provider is ever unlocked from it, since the request itself
    exists independently of whether the client unlocks any contact details.
    """
    classification = classification or {}
    service_request = ServiceRequest.objects.create(
        device_id=device_id,
        category=category,
        city=city,
        problem_description=problem_description,
        job_size=classification.get("job_size") or "",
        job_complexity=classification.get("job_complexity") or "",
        required_skills=classification.get("required_skills") or [],
        estimated_team_size=classification.get("estimated_team_size"),
        required_equipment=classification.get("required_equipment") or [],
        required_qualifications=classification.get("required_qualifications") or [],
    )

    providers = search_providers(category, city, force_refresh=force_refresh)
    _enrich(providers, city)

    # "Found" (not "searching") now that real results exist for this
    # request — still not "requested": no provider has been unlocked yet.
    if providers:
        service_request.status = ProviderMatch.STATUS_FOUND
        service_request.save(update_fields=["status", "updated_at"])

    place_ids = {provider["place_id"] for provider in providers if provider["place_id"]}
    unlocked_place_ids = set(
        ProviderMatch.objects.filter(device_id=device_id, place_id__in=place_ids).values_list(
            "place_id", flat=True
        )
    )

    data = RealProviderSerializer(providers, many=True, context={"unlocked_place_ids": unlocked_place_ids}).data
    return {
        "is_subscribed": _is_subscribed(device_id),
        "providers": data,
        "service_request_id": service_request.id,
    }


class ProviderSearchView(APIView):
    """GET /api/providers/search/?category=&city=&device_id=[&force_refresh=true]

    Real providers via Google Places (see provider_search.services). Every
    result is masked (see RealProviderSerializer) unless this device has
    already unlocked that specific place_id via ProviderUnlockView — an
    active Subscription does NOT change this response; it only means the
    device's next unlock of any one provider will be free instead of
    charging $4.99. `is_subscribed` is included as a hint for the client's
    unlock-prompt copy, not as a gate on this endpoint's data.
    """

    def get(self, request):
        category = request.query_params.get("category")
        city = request.query_params.get("city")
        device_id = request.query_params.get("device_id")

        if category not in CATEGORY_QUERIES:
            return Response(
                {"detail": f"category is required and must be one of {list(CATEGORY_QUERIES)}."}, status=400
            )
        if city not in CITIES:
            return Response({"detail": f"city is required and must be one of {CITIES}."}, status=400)
        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)

        force_refresh = request.query_params.get("force_refresh") == "true"

        try:
            result = _search_and_record(category, city, device_id, force_refresh=force_refresh)
        except RuntimeError as exc:
            return Response({"detail": str(exc)}, status=503)
        except requests.RequestException:
            return Response({"detail": "Could not reach the provider search service."}, status=502)

        return Response(result)


class ChatRefineView(APIView):
    """POST /api/chat/refine/ {"message": ..., "device_id": ..., "city": (optional)}

    Free-text alternative to the fixed category-tap onboarding flow: extracts
    a category/urgency/summary from what the client typed (see
    provider_search.chat_service.refine_request), then immediately runs the
    same search+record flow as ProviderSearchView so the chat goes straight
    from "what I typed" to "here are providers" in one round trip.
    """

    def post(self, request):
        text = (request.data.get("message") or "").strip()
        device_id = request.data.get("device_id")
        city = request.data.get("city") or "Edmonton"

        if not text:
            return Response({"detail": "message is required."}, status=400)
        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)
        if city not in CITIES:
            return Response({"detail": f"city must be one of {CITIES}."}, status=400)

        refined = refine_request(text)
        category = refined["category"]

        if category is None:
            return Response({
                "category": None,
                "urgency": refined["urgency"],
                "notes": refined["notes"],
                "is_subscribed": _is_subscribed(device_id),
                "providers": [],
            })

        try:
            result = _search_and_record(
                category, city, device_id, problem_description=text, classification=refined
            )
        except RuntimeError as exc:
            return Response({"detail": str(exc)}, status=503)
        except requests.RequestException:
            return Response({"detail": "Could not reach the provider search service."}, status=502)

        return Response({
            "category": category,
            "urgency": refined["urgency"],
            "notes": refined["notes"],
            "job_size": refined["job_size"],
            "job_complexity": refined["job_complexity"],
            "required_skills": refined["required_skills"],
            "estimated_team_size": refined["estimated_team_size"],
            "required_equipment": refined["required_equipment"],
            "required_qualifications": refined["required_qualifications"],
            **result,
        })


class ProviderUnlockView(APIView):
    """POST /api/providers/unlock/ {"device_id", "place_id", "category", "city", "paid": bool}

    The ONLY place a real phone number, address, or website is ever
    revealed, and the ONLY place a ProviderMatch ("Your requests" entry) is
    ever created — never as a side effect of search (see
    provider_search.views._search_and_record / RealProviderSerializer).

    Access is granted if the device has an active Subscription (free,
    unlimited), or if the client sets `"paid": true` (a one-off $4.99
    unlock). Like SubscriptionActivateView, `paid` is trusted from the
    client — there is no real payment processor wired up for this
    consumable purchase yet either; this is enough to exercise the gate
    end-to-end, not to bill anyone for real.

    Re-unlocking a provider this device already unlocked is a no-op that
    just refreshes its contact details and returns 200 — it never resets
    `status` or `unlock_method` on an existing row.
    """

    def post(self, request):
        device_id = request.data.get("device_id")
        place_id = request.data.get("place_id")
        category = request.data.get("category")
        city = request.data.get("city")
        paid = request.data.get("paid") is True

        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)
        if not place_id:
            return Response({"detail": "place_id is required."}, status=400)
        if category not in CATEGORY_QUERIES:
            return Response(
                {"detail": f"category is required and must be one of {list(CATEGORY_QUERIES)}."}, status=400
            )
        if city not in CITIES:
            return Response({"detail": f"city is required and must be one of {CITIES}."}, status=400)

        subscribed = _is_subscribed(device_id)
        if not subscribed and not paid:
            return Response(
                {
                    "detail": f"Subscribe or pay ${UNLOCK_PRICE_USD} to unlock this provider's contact details.",
                    "price_usd": UNLOCK_PRICE_USD,
                },
                status=402,
            )

        try:
            providers = search_providers(category, city)
        except RuntimeError as exc:
            return Response({"detail": str(exc)}, status=503)
        except requests.RequestException:
            return Response({"detail": "Could not reach the provider search service."}, status=502)

        provider = next((p for p in providers if p["place_id"] == place_id), None)
        if provider is None:
            return Response(
                {"detail": "That provider wasn't found for this category/city — try searching again."}, status=404
            )

        service_request = (
            ServiceRequest.objects.filter(device_id=device_id, category=category, city=city)
            .order_by("-created_at")
            .first()
        )
        match, created = ProviderMatch.objects.get_or_create(
            device_id=device_id,
            place_id=place_id,
            defaults={
                "category": category,
                "city": city,
                "provider_name": provider["name"],
                "provider_phone": provider["phone"],
                "provider_address": provider["address"],
                "provider_website": provider["website"],
                "service_request": service_request,
                "unlock_method": (
                    ProviderMatch.UNLOCK_METHOD_SUBSCRIPTION if subscribed else ProviderMatch.UNLOCK_METHOD_PAID
                ),
            },
        )
        if not created:
            match.provider_name = provider["name"]
            match.provider_phone = provider["phone"]
            match.provider_address = provider["address"]
            match.provider_website = provider["website"]
            match.save(update_fields=["provider_name", "provider_phone", "provider_address", "provider_website", "last_viewed_at"])

        _enrich([provider], city)
        data = RealProviderSerializer(provider, context={"unlocked_place_ids": {place_id}}).data
        return Response({"provider": data, "match_id": match.id, "match_status": match.status}, status=200)


class ProviderMatchListView(APIView):
    """GET /api/provider-matches/?device_id=

    The client's request/status pipeline: every provider this device has
    unlocked, each carrying its own status (see ProviderMatch.STATUS_CHOICES),
    newest first.
    """

    def get(self, request):
        device_id = request.query_params.get("device_id")
        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)

        matches = ProviderMatch.objects.filter(device_id=device_id).order_by("-last_viewed_at")
        return Response({"matches": ProviderMatchSerializer(matches, many=True).data})


class ProviderMatchStatusView(APIView):
    """POST /api/provider-matches/<id>/status/ {"device_id": ..., "status": ...}

    Lets the client manually advance (or archive) a request. Scoped to
    device_id as well as pk so one device can't rewrite another's status by
    guessing an id.
    """

    def post(self, request, pk):
        device_id = request.data.get("device_id")
        status_value = request.data.get("status")
        valid_statuses = dict(ProviderMatch.STATUS_CHOICES)
        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)
        if status_value not in valid_statuses:
            return Response({"detail": f"status must be one of {list(valid_statuses)}."}, status=400)

        try:
            match = ProviderMatch.objects.get(pk=pk, device_id=device_id)
        except ProviderMatch.DoesNotExist:
            return Response({"detail": "Not found."}, status=404)

        match.status = status_value
        # last_viewed_at is included explicitly (not just relying on
        # auto_now) so recent_contact_counts()'s 7-day window is measured
        # from when the status actually changed, not the original find.
        match.save(update_fields=["status", "last_viewed_at"])
        return Response(ProviderMatchSerializer(match).data)


class ProviderAvailabilityView(APIView):
    """GET/POST /api/provider-availability/?place_id=

    This platform's own "available now / busy" override for a real business
    (see ProviderAvailability's docstring on the trust limitation — there's
    no provider account system yet, so this trusts whoever calls it with the
    shared API key). GET returns the current value (available if no row
    exists yet); POST {"is_available_now": bool} sets it.
    """

    def get(self, request):
        place_id = request.query_params.get("place_id")
        if not place_id:
            return Response({"detail": "place_id is required."}, status=400)
        availability = ProviderAvailability.objects.filter(place_id=place_id).first()
        is_available_now = availability.is_available_now if availability else True
        return Response({"place_id": place_id, "is_available_now": is_available_now})

    def post(self, request):
        place_id = request.data.get("place_id")
        is_available_now = request.data.get("is_available_now")
        if not place_id:
            return Response({"detail": "place_id is required."}, status=400)
        if not isinstance(is_available_now, bool):
            return Response({"detail": "is_available_now must be a boolean."}, status=400)

        availability, _ = ProviderAvailability.objects.update_or_create(
            place_id=place_id, defaults={"is_available_now": is_available_now}
        )
        return Response({"place_id": place_id, "is_available_now": availability.is_available_now})


class KnownProvidersView(APIView):
    """GET /api/providers/known/

    Distinct (place_id, name) pairs already seen via search — lets the demo
    Provider Dashboard offer a "sign in as" picker of real businesses, since
    there's no provider account system to look this up from otherwise (see
    ProviderAvailability's docstring).
    """

    def get(self, request):
        rows = (
            ProviderMatch.objects.values("place_id", "provider_name")
            .distinct()
            .order_by("provider_name")[:200]
        )
        return Response({"providers": list(rows)})


class ProviderOnboardingView(APIView):
    """GET/POST /api/provider-onboarding/?provider_id=

    Structured provider sign-up, tracked as 5 independent sections
    (personal_info, services, service_area, credentials, photos) so a
    provider can complete them in any order across sessions —
    completion_percentage (see ProviderOnboarding) is what flags an
    incomplete profile for follow-up. `provider_id` is a self-issued
    identifier (see lib/provider/provider_id.dart), the same pattern as
    device_id.
    """

    def get(self, request):
        provider_id = request.query_params.get("provider_id")
        if not provider_id:
            return Response({"detail": "provider_id is required."}, status=400)
        onboarding, _ = ProviderOnboarding.objects.get_or_create(provider_id=provider_id)
        return Response(ProviderOnboardingSerializer(onboarding).data)

    def post(self, request):
        provider_id = request.data.get("provider_id")
        section = request.data.get("section")
        fields = request.data.get("fields")

        if not provider_id:
            return Response({"detail": "provider_id is required."}, status=400)
        if section not in ProviderOnboarding.SECTION_FIELDS:
            return Response(
                {"detail": f"section must be one of {sorted(ProviderOnboarding.SECTION_FIELDS)}."}, status=400
            )
        if not isinstance(fields, dict):
            return Response({"detail": "fields must be an object."}, status=400)

        onboarding, _ = ProviderOnboarding.objects.get_or_create(provider_id=provider_id)
        allowed = set(ProviderOnboarding.SECTION_FIELDS[section])
        changed = []
        for key, value in fields.items():
            if key not in allowed:
                continue
            setattr(onboarding, key, value)
            changed.append(key)

        if changed:
            onboarding.save(update_fields=[*changed, "updated_at"])
        return Response(ProviderOnboardingSerializer(onboarding).data)
