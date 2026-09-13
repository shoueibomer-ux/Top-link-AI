import hmac

from django.conf import settings
from rest_framework.permissions import BasePermission


class HasApiKey(BasePermission):
    """Requires a shared secret in the X-API-Key header.

    The app has no user-account system (profiles are anonymous, created
    per-request), so this isn't per-user auth — it's a shared secret between
    the official client and this backend, meant to keep the open internet
    (scanners, bots) from hitting the Claude-backed endpoints, not to
    withstand a targeted attacker who has extracted the key from the app.
    """

    message = "Missing or invalid API key."

    def has_permission(self, request, view):
        provided = request.headers.get("X-API-Key", "")
        return bool(settings.API_KEY) and hmac.compare_digest(provided, settings.API_KEY)
