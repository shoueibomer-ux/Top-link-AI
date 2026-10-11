from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils.decorators import method_decorator
from django_ratelimit.decorators import ratelimit
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import UserProfile, UserRole
from matching.permissions import HasApiKey

from .google_auth import GoogleAuthError, GoogleAuthNotConfigured, GoogleUser, verify_google_id_token
from .models import GoogleIdentity, ProviderProfile
from .serializers import ProviderProfileSerializer, PublicProviderSerializer

User = get_user_model()

_GOOGLE_SIGN_IN_RATE = "20/m"
MAX_MATCHES = 20


class IsProviderAccount(BasePermission):
    message = "Only provider accounts can do this."

    def has_permission(self, request, view):
        profile = getattr(request.user, "profile", None)
        return bool(profile and profile.role == UserRole.PROVIDER)


class AccountConflict(Exception):
    pass


def _user_for_google(google_user: GoogleUser):
    """(user, created). Looks the person up by their Google id first, then by
    a verified email that already belongs to a *provider* account. An email
    that belongs to a client account is refused rather than taken over."""
    with transaction.atomic():
        identity = GoogleIdentity.objects.select_related("user").filter(sub=google_user.sub).first()
        if identity:
            user, created = identity.user, False
        else:
            user = User.objects.filter(email__iexact=google_user.email).first()
            created = user is None
            if user is None:
                user = User.objects.create_user(username=google_user.email, email=google_user.email)
                user.set_unusable_password()
                user.save(update_fields=["password"])
                UserProfile.objects.create(user=user, role=UserRole.PROVIDER, full_name=google_user.name)
            GoogleIdentity.objects.create(user=user, sub=google_user.sub)

        profile = getattr(user, "profile", None)
        if profile is None or profile.role != UserRole.PROVIDER:
            raise AccountConflict("This email already belongs to a client account. Use a different Google account.")
        if not user.is_active:
            raise AccountConflict("This account has been disabled.")
        return user, created


class GoogleSignInView(APIView):
    """POST /api/provider/auth/google/ {"id_token": "..."}

    The app signs the provider in with Google and sends the ID token it got.
    The server verifies it (signature, expiry, that it was issued for our app,
    that the email is verified), finds or creates the provider's account, and
    returns that account's own JWT pair plus their profile, if they have one.
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
            user, created = _user_for_google(google_user)
        except AccountConflict as exc:
            return Response({"detail": str(exc)}, status=409)

        refresh = RefreshToken.for_user(user)
        profile = ProviderProfile.objects.filter(user=user).first()
        return Response({
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "email": user.email,
            "full_name": user.profile.full_name,
            "is_new_account": created,
            "profile": ProviderProfileSerializer(profile).data if profile else None,
        })


class ProviderProfileView(APIView):
    """/api/provider/profile/ — the signed-in provider's own profile.

    POST registers it (status starts as pending), GET returns it (404 until
    registered), PATCH edits it. Editing a rejected profile sends it back for
    review; editing an approved or pending one leaves its status alone.
    """

    permission_classes = [HasApiKey, IsAuthenticated, IsProviderAccount]

    def _mine(self, request):
        return ProviderProfile.objects.filter(user=request.user).first()

    def get(self, request):
        profile = self._mine(request)
        if profile is None:
            return Response({"detail": "You haven't registered a provider profile yet."}, status=404)
        return Response(ProviderProfileSerializer(profile).data)

    def post(self, request):
        if self._mine(request) is not None:
            return Response({"detail": "You have already registered. Edit your profile instead."}, status=409)
        serializer = ProviderProfileSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        extra = {} if "email" in serializer.validated_data else {"email": request.user.email}
        serializer.save(user=request.user, **extra)
        return Response(serializer.data, status=201)

    def patch(self, request):
        profile = self._mine(request)
        if profile is None:
            return Response({"detail": "You haven't registered a provider profile yet."}, status=404)
        serializer = ProviderProfileSerializer(profile, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        resubmit = {"status": ProviderProfile.STATUS_PENDING} if profile.status == ProviderProfile.STATUS_REJECTED else {}
        serializer.save(**resubmit)
        return Response(serializer.data)


class ProviderMatchesView(APIView):
    """GET /api/provider/matches/?category=<service slug>&city=<city>

    The providers a client may be matched with. Approved providers only:
    pending and rejected ones never appear. Shows business name, bio,
    services and cities, never contact details.
    """

    def get(self, request):
        category = request.query_params.get("category", "").strip()
        if not category:
            return Response({"detail": "category is required."}, status=400)
        city = request.query_params.get("city", "").strip()

        profiles = (
            ProviderProfile.objects.approved()
            .filter(categories__slug=category)
            .distinct()
            .prefetch_related("categories")
            .order_by("business_name")
        )
        if city:
            profiles = [p for p in profiles if city in (p.cities or [])]
        return Response({"results": PublicProviderSerializer(list(profiles)[:MAX_MATCHES], many=True).data})
