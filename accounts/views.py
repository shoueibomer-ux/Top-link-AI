from django.utils.decorators import method_decorator
from django_ratelimit.decorators import ratelimit
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenRefreshView as _TokenRefreshView

from matching.permissions import HasApiKey
from .serializers import ProfileUpdateSerializer, UserProfileSerializer

# Security audit finding H2: the token endpoint had no rate limiting. A trip
# returns a clean 429 (method_decorator + block=False + an explicit
# `request.limited` check) instead of django-ratelimit's default exception,
# which DRF would map to a 403.
_TOKEN_REFRESH_IP_RATE = "30/m"


class TokenRefreshView(_TokenRefreshView):
    """POST /api/accounts/token/refresh/ — same endpoint SimpleJWT already
    provided, just rate-limited (see module docstring) — a thin subclass
    only exists so there's a class here to attach the decorator to.
    """

    @method_decorator(ratelimit(key="ip", rate=_TOKEN_REFRESH_IP_RATE, method="POST", block=False))
    def post(self, request, *args, **kwargs):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many requests. Try again in a minute."}, status=429)
        return super().post(request, *args, **kwargs)


class MeView(APIView):
    """GET/PATCH /api/accounts/me/ — the authenticated user's role and name.

    PATCH {"full_name": ..., "email": ...} (either, both optional) edits the
    account holder's own name and sign-in email — see ProfileUpdateSerializer
    for what is deliberately not editable (role, password).
    """

    permission_classes = [HasApiKey, IsAuthenticated]

    def get(self, request):
        return Response(UserProfileSerializer(request.user.profile).data)

    def patch(self, request):
        profile = request.user.profile
        serializer = ProfileUpdateSerializer(profile, data=request.data, partial=True, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        profile.refresh_from_db()
        return Response(UserProfileSerializer(profile).data)
