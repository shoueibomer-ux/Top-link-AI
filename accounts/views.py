from django.utils.decorators import method_decorator
from django_ratelimit.decorators import ratelimit
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.views import TokenRefreshView as _TokenRefreshView

from matching.permissions import HasApiKey
from .models import ProviderBusinessProfile, UserRole
from .serializers import (
    EmailTokenObtainPairSerializer,
    ProviderBusinessProfileSerializer,
    RegisterSerializer,
    UserProfileSerializer,
)

# Security audit finding H2: none of these three endpoints had any rate
# limiting, so a password could be brute-forced against a real account with
# no cap at all. Two different keys, same idea as matching.views'
# `_AI_ENDPOINT_RATE` pattern (method_decorator + block=False + an explicit
# `request.limited` check, so a trip returns a clean 429 instead of
# django-ratelimit's default Ratelimited exception, which DRF would map to
# a 403 — the wrong status code for this).
_LOGIN_EMAIL_RATE = "5/m"  # per targeted account — the actual brute-force defense
_LOGIN_IP_RATE = "20/m"  # per source — catches one source hammering many accounts
_REGISTER_IP_RATE = "5/h"  # caps mass fake-account creation from one source
_TOKEN_REFRESH_IP_RATE = "30/m"


def _login_email_key(group, request):
    """django-ratelimit's built-in `post:email` key reads Django's
    request.POST, which is only populated for form-encoded bodies — this API
    is JSON, so request.POST is always empty there. Read the already-parsed
    DRF request.data instead, keyed on the account actually being attacked
    rather than (just) the source IP.
    """
    data = request.data if isinstance(request.data, dict) else {}
    return (data.get("email") or "").strip().lower()


class RegisterView(APIView):
    """POST /api/accounts/register/ {email, password, role, full_name, business_name?}

    Creates a real Customer or Provider account (see RegisterSerializer —
    role is restricted to customer/provider; admin accounts are never
    self-service). A provider registration also creates an empty
    ProviderBusinessProfile row, ready to be filled in via
    ProviderProfileView. Returns JWT tokens immediately (auto-login), same
    as LoginView.
    """

    @method_decorator(ratelimit(key="ip", rate=_REGISTER_IP_RATE, method="POST", block=False))
    def post(self, request):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many accounts created from this network. Try again later."}, status=429)

        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile = serializer.save()

        token_serializer = EmailTokenObtainPairSerializer(
            data={"email": profile.user.email, "password": request.data.get("password")}
        )
        token_serializer.is_valid(raise_exception=True)

        return Response(
            {
                **token_serializer.validated_data,
                "profile": UserProfileSerializer(profile).data,
            },
            status=status.HTTP_201_CREATED,
        )


class LoginView(TokenObtainPairView):
    """POST /api/accounts/login/ {email, password} -> {access, refresh}."""

    serializer_class = EmailTokenObtainPairSerializer

    # Stacked: both counters advance on every attempt; either tripping sets
    # request.limited (django-ratelimit ORs it across decorators), so a
    # single check below catches both.
    @method_decorator(ratelimit(key="ip", rate=_LOGIN_IP_RATE, method="POST", block=False))
    @method_decorator(ratelimit(key=_login_email_key, rate=_LOGIN_EMAIL_RATE, method="POST", block=False))
    def post(self, request, *args, **kwargs):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many login attempts. Try again in a minute."}, status=429)
        return super().post(request, *args, **kwargs)


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
    """GET /api/accounts/me/ — the authenticated user's role + profile
    (including their ProviderBusinessProfile, when they're a provider)."""

    permission_classes = [HasApiKey, IsAuthenticated]

    def get(self, request):
        return Response(UserProfileSerializer(request.user.profile).data)


class ProviderProfileView(APIView):
    """GET/PATCH /api/accounts/provider-profile/ — the authenticated
    provider's own business profile. 403s for a Customer account; this is
    the seed of the future Provider Dashboard's "Business Profile" section.
    """

    permission_classes = [HasApiKey, IsAuthenticated]

    def _get_profile_or_403(self, request):
        if request.user.profile.role != UserRole.PROVIDER:
            return None
        return ProviderBusinessProfile.objects.filter(user=request.user).first()

    def get(self, request):
        profile = self._get_profile_or_403(request)
        if profile is None:
            return Response({"detail": "Only provider accounts have a business profile."}, status=403)
        return Response(ProviderBusinessProfileSerializer(profile).data)

    def patch(self, request):
        profile = self._get_profile_or_403(request)
        if profile is None:
            return Response({"detail": "Only provider accounts have a business profile."}, status=403)
        serializer = ProviderBusinessProfileSerializer(profile, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
