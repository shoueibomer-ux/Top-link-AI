import requests
from django.utils import timezone
from rest_framework.views import APIView
from rest_framework.response import Response

from matching.models import Subscription
from .models import ProviderMatch
from .services import CATEGORY_QUERIES, CITIES, search_providers


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
            providers = search_providers(category, city, force_refresh=force_refresh)
        except RuntimeError as exc:
            return Response({"detail": str(exc)}, status=503)
        except requests.RequestException:
            return Response({"detail": "Could not reach the provider search service."}, status=502)

        if not _is_subscribed(device_id):
            preview = [
                {
                    "name": provider["name"],
                    "rating": provider["rating"],
                    "rating_count": provider["rating_count"],
                    "phone": _mask_phone(provider["phone"]),
                }
                for provider in providers
            ]
            return Response({"subscription_required": True, "providers": preview})

        for provider in providers:
            if not provider["place_id"]:
                continue
            ProviderMatch.objects.update_or_create(
                device_id=device_id,
                place_id=provider["place_id"],
                defaults={
                    "category": category,
                    "city": city,
                    "provider_name": provider["name"],
                    "provider_phone": provider["phone"],
                    "provider_address": provider["address"],
                    "provider_website": provider["website"],
                },
            )

        return Response({"subscription_required": False, "providers": providers})
