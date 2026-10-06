from django.utils.decorators import method_decorator
from django_ratelimit.decorators import ratelimit
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from catalog.taxonomy import active_service_names, launched_slugs, wants_unlaunched

from .models import Profile, MatchRequest, Category
from .serializers import (
    ProfileCreateSerializer, MatchRequestCreateSerializer, MatchResultSerializer,
)
# Tested standalone in matching_engine.py — same logic, imported here unchanged.
from .matching_engine import (
    Profile as EngineProfile, MatchRequest as EngineMatchRequest,
    find_matches, ai_categorize, keyword_suggestions, rank_keyword_categories,
)

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


class CategorySuggestView(APIView):
    """GET /api/categories/suggest/?q=<partly typed text>

    Search-as-you-type for the app's category search bar: which categories the
    text points at (`categories`, best first, the same keyword classifier
    ai_categorize() falls back to) and which
    taxonomy keywords the text is heading toward (`keywords`).

    Like CategoryProvidersView this deliberately never calls the Claude API:
    it runs on every pause in typing, and free-form requests that need real
    understanding belong to Ask AI (ChatRefineView), not to a search box.

    Launched services only by default; `?include_unlaunched=true` adds every
    other active service so the app can offer its waitlist flow for them.
    """

    MAX_QUERY_LENGTH = 100

    def get(self, request):
        query = " ".join(request.query_params.get("q", "").split())[: self.MAX_QUERY_LENGTH]
        slugs = set(active_service_names()) if wants_unlaunched(request) else launched_slugs()
        return Response({
            "query": query,
            "categories": rank_keyword_categories(query, slugs) if query else [],
            "keywords": keyword_suggestions(query, slugs=slugs),
        })
