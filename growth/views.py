from datetime import timedelta

from django.utils import timezone
from django.utils.decorators import method_decorator
from django_ratelimit.decorators import ratelimit
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsClientAccount
from config.site_url import absolute_url
from matching.permissions import HasApiKey
from providers.models import ProviderProfile

from . import links
from .models import InviteCode, InviteSignup, ReminderPreference

# An invite only counts for an account that is new: someone who has used Tabmatch for months didn't join
# because of it.
CLAIM_WINDOW = timedelta(days=30)


def _invite_url(request, code: str) -> str:
    return absolute_url(request, links.invite_path(code))


class InviteView(APIView):
    """GET /api/growth/invite/   (signed-in client)

    The client's own invite link, made on first use. The app appends
    ?provider=<id> to share a provider they used ("Share this provider")."""

    permission_classes = [HasApiKey, IsAuthenticated, IsClientAccount]

    def get(self, request):
        invite = InviteCode.for_user(request.user)
        url = _invite_url(request, invite.code)
        return Response({
            "code": invite.code,
            "url": url,
            "share_text": f"I use Tabmatch to find trusted local service providers in Edmonton. Join with my link: {url}",
            "signups": invite.signups.count(),
        })


class InviteClaimView(APIView):
    """POST /api/growth/invite/claim/ {"code": "...", "provider_id": (optional)}   (signed-in client)

    Records that this new client came through an invite: the app sends it
    right after sign-in when it was opened from an invite link, or when the
    person types a friend's code. Only once per account, never one's own
    code, and only within CLAIM_WINDOW of the account being created."""

    permission_classes = [HasApiKey, IsAuthenticated, IsClientAccount]

    @method_decorator(ratelimit(key="user_or_ip", rate="10/h", method="POST", block=False))
    def post(self, request):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many attempts. Try again later."}, status=429)
        code = request.data.get("code")
        code = code.strip().upper() if isinstance(code, str) else ""
        invite = InviteCode.objects.filter(code=code).select_related("user").first() if code else None
        if invite is None or not invite.user.is_active:
            return Response({"detail": "That invite code isn't valid."}, status=400)
        if invite.user_id == request.user.pk:
            return Response({"detail": "That's your own invite code."}, status=400)
        if InviteSignup.objects.filter(invitee=request.user).exists():
            return Response({"detail": "An invite is already recorded for this account."}, status=409)
        if request.user.date_joined < timezone.now() - CLAIM_WINDOW:
            return Response({"detail": "Invite codes are for new accounts."}, status=409)
        provider_id = request.data.get("provider_id")
        provider = (
            ProviderProfile.objects.approved().filter(pk=provider_id).first()
            if isinstance(provider_id, int) and not isinstance(provider_id, bool)
            else None
        )
        InviteSignup.objects.create(invitee=request.user, invite=invite, code=invite.code, shared_provider=provider)
        return Response({"claimed": True}, status=201)


class ReminderPreferenceView(APIView):
    """GET/PATCH /api/growth/reminders/ {"seasonal_reminders": bool}   (signed-in client)

    The Settings switch for seasonal reminders (push and email together)."""

    permission_classes = [HasApiKey, IsAuthenticated, IsClientAccount]

    def get(self, request):
        return Response({"seasonal_reminders": ReminderPreference.enabled_for(request.user)})

    def patch(self, request):
        value = request.data.get("seasonal_reminders")
        if not isinstance(value, bool):
            return Response({"detail": "seasonal_reminders must be true or false."}, status=400)
        pref = ReminderPreference.set_for(request.user, value, ReminderPreference.VIA_APP)
        return Response({"seasonal_reminders": pref.seasonal_reminders})
