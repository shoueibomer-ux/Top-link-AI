"""Push notifications through Firebase Cloud Messaging (the HTTP v1 API). The only module that talks to FCM.

The text is deliberately generic ("<name> sent you a message"): the message itself never leaves the app, so
it can't show on a lock screen. Sending can never break a request: any failure is logged and swallowed.
Without FCM_SERVICE_ACCOUNT_JSON, push is simply off."""

import json
import logging

import requests
from django.conf import settings

from .models import DeviceToken

logger = logging.getLogger(__name__)

SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
TIMEOUT_SECONDS = 5

_credentials = None
_credentials_source = None


def configured() -> bool:
    return bool(settings.FCM_SERVICE_ACCOUNT_JSON)


def _project_id_and_token():
    """(project id, a valid OAuth access token) for the service account in settings."""
    global _credentials, _credentials_source
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    raw = settings.FCM_SERVICE_ACCOUNT_JSON
    info = json.loads(raw)
    if _credentials is None or _credentials_source != raw:
        _credentials = service_account.Credentials.from_service_account_info(info, scopes=[SCOPE])
        _credentials_source = raw
    if not _credentials.valid:
        _credentials.refresh(Request())
    return info["project_id"], _credentials.token


def _send_one(project_id: str, access_token: str, token: str, payload: dict) -> str:
    """"ok", "dead" (the phone no longer has the app: forget the token) or "error"."""
    response = requests.post(
        f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send",
        headers={"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"},
        json={"message": {"token": token, **payload}},
        timeout=TIMEOUT_SECONDS,
    )
    if response.status_code == 200:
        return "ok"
    status = ""
    try:
        status = response.json().get("error", {}).get("status", "")
    except ValueError:
        pass
    if response.status_code == 404 or status in ("NOT_FOUND", "UNREGISTERED"):
        return "dead"
    logger.warning("FCM send failed: HTTP %s %s", response.status_code, status)
    return "error"


def send_to_user(user, title: str, body: str, data: dict) -> int:
    """Sends a notification to every phone `user` has registered. Returns how many were accepted by FCM.
    Never raises."""
    if not configured():
        return 0
    try:
        tokens = list(DeviceToken.objects.filter(user=user).values_list("token", flat=True))
        if not tokens:
            return 0
        project_id, access_token = _project_id_and_token()
        payload = {
            "notification": {"title": title, "body": body},
            "data": {key: str(value) for key, value in data.items()},
            "android": {"priority": "HIGH"},
        }
        sent = 0
        for token in tokens:
            result = _send_one(project_id, access_token, token, payload)
            if result == "ok":
                sent += 1
            elif result == "dead":
                DeviceToken.objects.filter(token=token).delete()
        return sent
    except Exception:  # noqa: BLE001 - push must never break the request that triggered it
        logger.exception("Could not send push notification")
        return 0


def notify_new_message(message) -> int:
    """Tells the other person in the conversation that a message arrived (never what it says)."""
    conversation = message.conversation
    recipient = conversation.other_user(message.sender)
    if recipient is None:
        return 0
    sender_name = conversation.display_name_for(recipient)
    return send_to_user(
        recipient,
        title="New message",
        body=f"{sender_name} sent you a message.",
        data={"type": "chat", "conversation_id": conversation.pk},
    )
