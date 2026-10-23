import logging

from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from django.utils.decorators import method_decorator
from django_ratelimit.core import is_ratelimited
from django_ratelimit.decorators import ratelimit
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenRefreshView as _TokenRefreshView

from matching.permissions import HasApiKey
from providers.google_auth import GoogleAuthError, GoogleAuthNotConfigured, verify_google_id_token
from providers.google_signin import AccountConflict, user_for_google
from providers.models import ProviderProfile
from providers.serializers import ProviderProfileSerializer

from . import email_login

from .deletion import CONFIRM_WORD, AccountNotDeletable, delete_account
from .models import AccountDeletion, UserRole
from .serializers import ProfileUpdateSerializer, UserProfileSerializer

# Security audit finding H2: the token endpoint had no rate limiting. A trip
# returns a clean 429 (method_decorator + block=False + an explicit
# `request.limited` check) instead of django-ratelimit's default exception,
# which DRF would map to a 403.
_TOKEN_REFRESH_IP_RATE = "30/m"
_GOOGLE_SIGN_IN_RATE = "20/m"

logger = logging.getLogger(__name__)


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


# Email sign-in (accounts.email_login). Sends are limited per address and per IP; checking a code per address
# and per IP on top of the 5 wrong tries a single code allows.
_EMAIL_SEND_IP_RATE = "20/h"
_EMAIL_SEND_ADDRESS_RATE = "5/h"
_EMAIL_VERIFY_IP_RATE = "30/h"
_EMAIL_VERIFY_ADDRESS_RATE = "15/h"
_EMAIL_CODE_SENT = "If that address can receive email, a 6-digit code is on its way. It expires in 10 minutes."
_EMAIL_CODE_INVALID = "That code is wrong or has expired. Check it, or ask for a new one."
_EMAIL_UNAVAILABLE = "Email sign-in isn't available right now. Use Google instead."


def _email_and_role(request):
    email = email_login.normalize(request.data.get("email"))
    try:
        validate_email(email)
    except ValidationError:
        email = ""
    return email, email_login.ROLES.get(request.data.get("role"))


def _address_limited(request, group: str, email: str, rate: str) -> bool:
    return is_ratelimited(request, group=group, key=lambda _group, _request: email, rate=rate, increment=True)


class EmailLoginStatusView(APIView):
    """GET /api/accounts/email/status/ — whether "Continue with email" should be shown."""

    def get(self, request):
        return Response({"enabled": email_login.enabled()})


class EmailLoginStartView(APIView):
    """POST /api/accounts/email/start/ {"email": "...", "role": "customer" | "provider"}

    Sends a sign-in code. Answers the same whether or not the email has an account."""

    @method_decorator(ratelimit(key="ip", rate=_EMAIL_SEND_IP_RATE, method="POST", block=False))
    def post(self, request):
        if not email_login.enabled():
            return Response({"detail": _EMAIL_UNAVAILABLE}, status=503)
        if getattr(request, "limited", False):
            return Response({"detail": "Too many codes requested. Try again later."}, status=429)
        email, role = _email_and_role(request)
        if role is None:
            return Response({"detail": "role must be customer or provider."}, status=400)
        if not email:
            return Response({"detail": "Enter a valid email address."}, status=400)
        if _address_limited(request, "email-login-send", email, _EMAIL_SEND_ADDRESS_RATE):
            return Response({"detail": "Too many codes requested. Try again later."}, status=429)
        try:
            email_login.send_code(email, role)
        except Exception:  # noqa: BLE001 - a mail server problem; logged, and the person is told to try Google
            logger.exception("Could not send an email sign-in code")
            return Response({"detail": _EMAIL_UNAVAILABLE}, status=503)
        return Response({"detail": _EMAIL_CODE_SENT})


class EmailLoginVerifyView(APIView):
    """POST /api/accounts/email/verify/ {"email", "role", "code"}

    Signs in with the code: the same answer as the Google sign-in for that role (tokens, plus the provider
    profile for a provider). A new email gets a new account; an email already on an account signs into it."""

    @method_decorator(ratelimit(key="ip", rate=_EMAIL_VERIFY_IP_RATE, method="POST", block=False))
    def post(self, request):
        if not email_login.enabled():
            return Response({"detail": _EMAIL_UNAVAILABLE}, status=503)
        if getattr(request, "limited", False):
            return Response({"detail": "Too many attempts. Try again later."}, status=429)
        email, role = _email_and_role(request)
        if role is None:
            return Response({"detail": "role must be customer or provider."}, status=400)
        if not email:
            return Response({"detail": _EMAIL_CODE_INVALID}, status=400)
        if _address_limited(request, "email-login-verify", email, _EMAIL_VERIFY_ADDRESS_RATE):
            return Response({"detail": "Too many attempts. Try again later."}, status=429)
        try:
            email_login.check_code(email, role, request.data.get("code"))
        except email_login.CodeInvalid:
            return Response({"detail": _EMAIL_CODE_INVALID}, status=400)
        try:
            user, created = email_login.user_for_email(email, role)
        except email_login.AccountConflict as exc:
            return Response({"detail": str(exc)}, status=409)

        refresh = RefreshToken.for_user(user)
        body = {
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "email": user.email,
            "full_name": user.profile.full_name,
            "is_new_account": created,
        }
        if role == UserRole.PROVIDER:
            profile = ProviderProfile.objects.filter(user=user).first()
            body["profile"] = ProviderProfileSerializer(profile).data if profile else None
        return Response(body)
