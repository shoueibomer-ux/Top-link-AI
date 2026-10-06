import hmac

from django.conf import settings
from rest_framework.exceptions import NotAuthenticated
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
        # Compared as bytes: compare_digest raises TypeError (a 500) on a
        # str containing non-ASCII characters, which a client can send.
        provided = request.headers.get("X-API-Key", "").encode("utf-8")
        expected = settings.API_KEY.encode("utf-8")
        if expected and hmac.compare_digest(provided, expected):
            return True
        # With JWT authentication configured, DRF's own denial path answers
        # an unauthenticated request with 401 "Authentication credentials
        # were not provided." — which reads like a missing login, not a bad
        # key, and hid this cause. Raise it ourselves with the real reason;
        # the status stays 401, and a request that did authenticate (valid
        # Bearer token, wrong key) still gets the plain 403 below.
        if request.authenticators and not request.successful_authenticator:
            raise NotAuthenticated(self.message)
        return False
