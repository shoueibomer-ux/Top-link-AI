from django.utils.decorators import method_decorator
from django_ratelimit.decorators import ratelimit
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenRefreshView as _TokenRefreshView

from matching.permissions import HasApiKey
from providers.google_auth import GoogleAuthError, GoogleAuthNotConfigured, verify_google_id_token
from providers.google_signin import AccountConflict, user_for_google

from .deletion import CONFIRM_WORD, AccountNotDeletable, delete_account
from .models import AccountDeletion, UserRole
from .serializers import ProfileUpdateSerializer, UserProfileSerializer

# Security audit finding H2: the token endpoint had no rate limiting. A trip
# returns a clean 429 (method_decorator + block=False + an explicit
# `request.limited` check) instead of django-ratelimit's default exception,
# which DRF would map to a 403.
_TOKEN_REFRESH_IP_RATE = "30/m"
_GOOGLE_SIGN_IN_RATE = "20/m"


class ClientGoogleSignInView(APIView):
    """POST /api/accounts/google/ {"id_token": "..."}

    The client's way in: the app signs the person in with Google and sends the
    ID token. The server verifies it (same checks as the provider sign-in),
    finds or creates their *client* account, and returns that account's own JWT
    pair. An email that belongs to a provider account is refused (409): one
    Google account is one role.
    """

    @method_decorator(ratelimit(key="ip", rate=_GOOGLE_SIGN_IN_RATE, method="POST", block=False))
    def post(self, request):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many sign-in attempts. Try again in a minute."}, status=429)
        try:
            google_user = verify_google_id_token(request.data.get("id_token"))
        except GoogleAuthNotConfigured as exc:
            return Response({"detail": str(exc)}, status=503)
        except GoogleAuthError as exc:
            return Response({"detail": str(exc)}, status=401)

        try:
            user, created = user_for_google(google_user, UserRole.CUSTOMER)
        except AccountConflict as exc:
            return Response({"detail": str(exc)}, status=409)

        refresh = RefreshToken.for_user(user)
        return Response({
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "email": user.email,
            "full_name": user.profile.full_name,
            "is_new_account": created,
        })


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


class DeleteAccountView(APIView):
    """POST /api/accounts/delete/ {"confirm": "DELETE"}   (the signed-in client or provider)

    Deletes the caller's own account: see accounts.deletion for exactly what goes and what is kept anonymised.
    The word has to be typed so a stray request can't do it. Only ever the caller's own account; staff accounts
    are refused. The app signs the person out afterwards."""

    permission_classes = [HasApiKey, IsAuthenticated]

    @method_decorator(ratelimit(key="user_or_ip", rate="5/h", method="POST", block=False))
    def post(self, request):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many attempts. Try again later."}, status=429)
        if request.data.get("confirm") != CONFIRM_WORD:
            return Response({"detail": f"Type {CONFIRM_WORD} to confirm."}, status=400)
        try:
            delete_account(request.user, via=AccountDeletion.VIA_APP)
        except AccountNotDeletable as exc:
            return Response({"detail": str(exc)}, status=403)
        return Response({"deleted": True})


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
