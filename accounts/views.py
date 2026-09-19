from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView

from matching.permissions import HasApiKey
from .models import ProviderBusinessProfile, UserRole
from .serializers import (
    EmailTokenObtainPairSerializer,
    ProviderBusinessProfileSerializer,
    RegisterSerializer,
    UserProfileSerializer,
)


class RegisterView(APIView):
    """POST /api/accounts/register/ {email, password, role, full_name, business_name?}

    Creates a real Customer or Provider account (see RegisterSerializer —
    role is restricted to customer/provider; admin accounts are never
    self-service). A provider registration also creates an empty
    ProviderBusinessProfile row, ready to be filled in via
    ProviderProfileView. Returns JWT tokens immediately (auto-login), same
    as LoginView.
    """

    def post(self, request):
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
