"""Verifying the Google ID token the app sends. The only module that talks to
Google; tests replace verify_google_id_token or mock the library call."""

from dataclasses import dataclass

from django.conf import settings
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

DEV_FAKE_PREFIX = "dev-fake:"


class GoogleAuthError(Exception):
    """The token isn't acceptable (bad signature, expired, wrong app, ...)."""


class GoogleAuthNotConfigured(Exception):
    """The server has no Google client ID to check tokens against."""


@dataclass
class GoogleUser:
    sub: str
    email: str
    name: str


def verify_google_id_token(token: str) -> GoogleUser:
    if not isinstance(token, str) or not token.strip():
        raise GoogleAuthError("No Google token was provided.")
    token = token.strip()

    # Development only (refused at startup outside DEBUG, see providers.checks):
    # lets the emulator exercise the flow without a Google Cloud project.
    if settings.GOOGLE_DEV_FAKE_AUTH and settings.DEBUG and token.startswith(DEV_FAKE_PREFIX):
        email = token[len(DEV_FAKE_PREFIX):].strip().lower()
        if "@" not in email:
            raise GoogleAuthError("Fake Google token needs an email.")
        return GoogleUser(sub=f"dev-fake-{email}", email=email, name=email.split("@")[0].title())

    client_ids = settings.GOOGLE_OAUTH_CLIENT_IDS
    if not client_ids:
        raise GoogleAuthNotConfigured("Google sign-in is not configured on the server.")

    try:
        # Checks the signature against Google's keys, the expiry and the issuer.
        info = id_token.verify_oauth2_token(token, google_requests.Request())
    except ValueError as exc:
        raise GoogleAuthError("That Google sign-in could not be verified.") from exc

    if info.get("aud") not in client_ids:
        raise GoogleAuthError("That Google sign-in was issued for a different app.")
    if not info.get("email_verified"):
        raise GoogleAuthError("That Google account's email is not verified.")
    email = (info.get("email") or "").strip().lower()
    if not email or not info.get("sub"):
        raise GoogleAuthError("That Google sign-in has no email.")
    return GoogleUser(sub=info["sub"], email=email, name=info.get("name", "") or "")
