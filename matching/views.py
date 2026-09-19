from django.utils.decorators import method_decorator
from django_ratelimit.decorators import ratelimit
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from .models import Profile, MatchRequest, Category, Subscription
from .serializers import (
    ProfileCreateSerializer, MatchRequestCreateSerializer, MatchResultSerializer,
    SubscriptionSerializer, SubscriptionActivateSerializer,
)
# Tested standalone in matching_engine.py — same logic, imported here unchanged.
from .matching_engine import (
    Profile as EngineProfile, MatchRequest as EngineMatchRequest,
    find_matches, ai_categorize,
)
from notifications.services import notify

# Stricter than the general API default (60/min) because both views below
# call the paid Claude API via ai_categorize().
_AI_ENDPOINT_RATE = "10/m"


@method_decorator(ratelimit(key="ip", rate=_AI_ENDPOINT_RATE, method="POST", block=False), name="post")
class ProfileCreateView(APIView):
    """POST /api/profiles/  — description is required; categories are assigned automatically."""

    def post(self, request):
        if getattr(request, "limited", False):
            return Response({"detail": "Rate limit exceeded. Try again later."}, status=429)

        serializer = ProfileCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile = serializer.save()

        category_names = ai_categorize(profile.description)
        categories = [Category.objects.get_or_create(name=c)[0] for c in category_names]
        profile.categories.set(categories)

        return Response(ProfileCreateSerializer(profile).data, status=status.HTTP_201_CREATED)


@method_decorator(ratelimit(key="ip", rate=_AI_ENDPOINT_RATE, method="POST", block=False), name="post")
class MatchView(APIView):
    """POST /api/match/  — request_text is required; returns ranked matches with transparent scores."""

    def post(self, request):
        if getattr(request, "limited", False):
            return Response({"detail": "Rate limit exceeded. Try again later."}, status=429)

        serializer = MatchRequestCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        match_request = serializer.save()

        category_names = ai_categorize(match_request.request_text)
        categories = [Category.objects.get_or_create(name=c)[0] for c in category_names]
        match_request.categories.set(categories)

        candidates = [
            EngineProfile(
                id=str(p.id), name=p.name, role=p.role,
                categories={c.name for c in p.categories.all()},
                lat=p.lat, lng=p.lng, available=p.available, rating=p.rating,
            )
            for p in Profile.objects.filter(available=True).exclude(id=match_request.requester_id)
        ]

        engine_request = EngineMatchRequest(
            requester_id=str(match_request.requester_id),
            categories={c.name for c in categories},
            lat=match_request.lat, lng=match_request.lng,
            max_distance_km=match_request.max_distance_km,
        )

        results = find_matches(engine_request, candidates)

        payload = [
            {
                "profile": Profile.objects.get(id=int(r.profile.id)),
                "score": r.score,
                "breakdown": r.breakdown,
            }
            for r in results
        ]
        return Response(MatchResultSerializer(payload, many=True).data)


class CategoryProvidersView(APIView):
    """GET /api/providers/?category=<slug>&lat=&lng=

    Lightweight provider preview for the onboarding category detail page —
    the category is already known at that point (no free text to classify),
    so this deliberately skips ai_categorize() entirely rather than reusing
    MatchView. That avoids spending Claude API calls and burning the AI
    endpoints' rate limit every time a user taps into a category card, and
    avoids creating a throwaway Profile/MatchRequest row per preview.
    """

    def get(self, request):
        category_name = request.query_params.get("category")
        if not category_name:
            return Response({"detail": "category is required."}, status=400)

        try:
            lat = float(request.query_params["lat"])
            lng = float(request.query_params["lng"])
        except (KeyError, TypeError, ValueError):
            return Response({"detail": "lat and lng are required and must be numeric."}, status=400)

        candidates = [
            EngineProfile(
                id=str(p.id), name=p.name, role=p.role,
                categories={c.name for c in p.categories.all()},
                lat=p.lat, lng=p.lng, available=p.available, rating=p.rating,
            )
            for p in Profile.objects.filter(available=True, categories__name=category_name)
        ]

        engine_request = EngineMatchRequest(
            requester_id="",
            categories={category_name},
            lat=lat, lng=lng,
        )
        results = find_matches(engine_request, candidates, top_n=10)

        payload = [
            {
                "profile": Profile.objects.get(id=int(r.profile.id)),
                "score": r.score,
                "breakdown": r.breakdown,
            }
            for r in results
        ]
        return Response(MatchResultSerializer(payload, many=True).data)


class SubscriptionStatusView(APIView):
    """GET /api/subscription/?device_id=...  — current paywall status for a device."""

    def get(self, request):
        device_id = request.query_params.get("device_id")
        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)

        subscription = Subscription.objects.filter(device_id=device_id).first()
        if subscription is None:
            return Response({
                "device_id": device_id,
                "status": "inactive",
                "start_date": None,
                "expiry_date": None,
            })
        return Response(SubscriptionSerializer(subscription).data)


class SubscriptionActivateView(APIView):
    """POST /api/subscription/activate/  — record a completed purchase for a device.

    NOTE: this trusts whatever the client sends — there is no App Store/Play
    Store receipt validation here yet. It's enough to build and test the
    paywall gate end-to-end, but must not be treated as real billing
    verification until that's added.
    """

    def post(self, request):
        serializer = SubscriptionActivateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        subscription, created = Subscription.objects.update_or_create(
            device_id=data["device_id"],
            defaults={
                "status": data["status"],
                "start_date": data["start_date"],
                "expiry_date": data["expiry_date"],
            },
        )
        if created:
            notify(
                data["device_id"],
                "Welcome to Top Link AI",
                "Your subscription is active. Start browsing real, verified providers near you.",
            )
        return Response(SubscriptionSerializer(subscription).data, status=status.HTTP_200_OK)
