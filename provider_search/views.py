import requests
from django.utils import timezone
from rest_framework.views import APIView
from rest_framework.response import Response

from matching.models import Subscription
from notifications.services import notify
from .chat_service import refine_request
from .models import ProviderAvailability, ProviderMatch, ProviderOnboarding, ServiceRequest
from .serializers import ProviderMatchSerializer, ProviderOnboardingSerializer
from .services import (
    CATEGORY_QUERIES,
    CITIES,
    availability_map,
    estimated_response_minutes,
    recent_contact_counts,
    search_providers,
)


def _is_subscribed(device_id: str) -> bool:
    subscription = Subscription.objects.filter(device_id=device_id).first()
    if subscription is None or subscription.status not in ("trial", "active"):
        return False
    if subscription.expiry_date and subscription.expiry_date < timezone.now():
        return False
    return True


def _mask_phone(phone: str) -> str:
    """First 4 characters visible, the rest replaced with dots — enough to
    show a real number exists without giving away a way to contact it."""
    if not phone:
        return ""
    visible = phone[:4]
    return visible + "•" * max(len(phone) - len(visible), 0)


def _search_and_record(
    category: str,
    city: str,
    device_id: str,
    force_refresh: bool = False,
    problem_description: str = "",
    classification: dict | None = None,
) -> dict:
    """Shared by ProviderSearchView and ChatRefineView: search Google Places
    for `category`/`city`, then either mask the results (no subscription) or
    record each as a ProviderMatch and notify on newly-seen providers
    (subscribed). Returns the dict to use directly as a Response body, or
    raises RuntimeError/requests.RequestException same as search_providers.

    `problem_description` is only ever non-blank when called from the chat
    flow (see ChatRefineView) — the fixed category-tap flow has no free text
    to record, so it's left blank there rather than fabricated. Likewise
    `classification` (job_size/job_complexity/etc., from
    chat_service.refine_request) is only ever populated from chat.

    Build plan Phase 1A, task 4: every call creates a ServiceRequest — the
    "job" anchor Phase 1B's matching and Phase 1C's Leads read from — even
    for an unsubscribed preview search, since the request itself exists
    independently of whether the client can see full contact details yet.
    ProviderMatch rows created below are linked to it via the nullable
    `service_request` FK; this does not change ProviderMatch's own shape or
    the History tab's API.
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
    place_ids = [provider["place_id"] for provider in providers if provider["place_id"]]

    # Social proof and the availability badge are shown on both masked and
    # full cards — engagement/availability signal is useful before someone
    # subscribes too. Response-time is only meaningful once a client has
    # actually unlocked a provider, so it's attached to full results only.
    contact_counts = recent_contact_counts(place_ids)
    availability = availability_map(place_ids)
    for provider in providers:
        provider["recent_contact_count"] = contact_counts.get(provider["place_id"], 0)
        provider["is_available_now"] = availability.get(provider["place_id"], True)

    if not _is_subscribed(device_id):
        preview = [
            {
                "name": provider["name"],
                "rating": provider["rating"],
                "rating_count": provider["rating_count"],
                "phone": _mask_phone(provider["phone"]),
                "recent_contact_count": provider["recent_contact_count"],
                "is_available_now": provider["is_available_now"],
            }
            for provider in providers
        ]
        return {"subscription_required": True, "providers": preview, "service_request_id": service_request.id}

    new_provider_count = 0
    for provider in providers:
        if not provider["place_id"]:
            continue
        provider["estimated_response_minutes"] = estimated_response_minutes(provider["place_id"])
        defaults = {
            "category": category,
            "city": city,
            "provider_name": provider["name"],
            "provider_phone": provider["phone"],
            "provider_address": provider["address"],
            "provider_website": provider["website"],
            # Always points at the request that most recently touched this
            # row — later plain (non-chat) searches re-touching a match
            # still attach it to their own ServiceRequest.
            "service_request": service_request,
        }
        # Only set when we actually have one — a later plain (non-chat)
        # search re-touching this row must not blank out a description a
        # previous chat search already recorded.
        if problem_description:
            defaults["problem_description"] = problem_description
        _, created = ProviderMatch.objects.update_or_create(
            device_id=device_id,
            place_id=provider["place_id"],
            defaults=defaults,
        )
        if created:
            new_provider_count += 1

    # Only notify when this device hasn't seen these providers before —
    # otherwise re-opening the same category/city would spam a
    # notification on every preview.
    if new_provider_count > 0:
        plural = "s" if new_provider_count != 1 else ""
        notify(
            device_id,
            f"{new_provider_count} new {category} provider{plural} found",
            f"We found {new_provider_count} verified provider{plural} in {city} ready to help.",
            category=category,
        )

    return {"subscription_required": False, "providers": providers, "service_request_id": service_request.id}


class ProviderSearchView(APIView):
    """GET /api/providers/search/?category=&city=&device_id=[&force_refresh=true]

    Real providers via Google Places (see provider_search.services), gated
    behind the same device-based Subscription used everywhere else in this
    app (matching.models.Subscription / matching.views.SubscriptionStatusView):
    subscribed devices get full contact info and every provider they see is
    recorded in ProviderMatch; unsubscribed devices get a masked preview and
    `subscription_required: true`.
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
                "subscription_required": False,
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
