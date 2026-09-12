from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from .models import Profile, MatchRequest, Category
from .serializers import (
    ProfileCreateSerializer, MatchRequestCreateSerializer, MatchResultSerializer,
)
# Tested standalone in matching_engine.py — same logic, imported here unchanged.
from .matching_engine import (
    Profile as EngineProfile, MatchRequest as EngineMatchRequest,
    find_matches, ai_categorize,
)


class ProfileCreateView(APIView):
    """POST /api/profiles/  — description is required; categories are assigned automatically."""

    def post(self, request):
        serializer = ProfileCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile = serializer.save()

        category_names = ai_categorize(profile.description)
        categories = [Category.objects.get_or_create(name=c)[0] for c in category_names]
        profile.categories.set(categories)

        return Response(ProfileCreateSerializer(profile).data, status=status.HTTP_201_CREATED)


class MatchView(APIView):
    """POST /api/match/  — request_text is required; returns ranked matches with transparent scores."""

    def post(self, request):
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
