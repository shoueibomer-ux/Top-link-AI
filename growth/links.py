"""Every link the growth features hand out, in one place: the app deep links
(tabmatch://open/...), the website pages that offer them (/open/request/,
/invite/<code>/), and the signed unsubscribe link in reminder emails."""

from urllib.parse import urlencode

from django.core import signing

APP_SCHEME = "tabmatch"
_UNSUBSCRIBE_SALT = "growth.reminders.unsubscribe"


def app_request_link(service: str, source: str = "", ref: str = "") -> str:
    """Opens the app's request flow with `service` chosen (see lib/growth/growth_links.dart)."""
    params = {"service": service}
    if source:
        params["src"] = source
    if ref:
        params["ref"] = ref
    return f"{APP_SCHEME}://open/request?{urlencode(params)}"


def app_invite_link(code: str, provider_id: int | None = None) -> str:
    params = {"code": code}
    if provider_id:
        params["provider"] = provider_id
    return f"{APP_SCHEME}://open/invite?{urlencode(params)}"


def open_request_path(service: str, source: str = "", ref: str = "") -> str:
    """The website page that sends someone into the app's request flow (or to get the app)."""
    params = {"service": service}
    if source:
        params["src"] = source
    if ref:
        params["ref"] = ref
    return f"/open/request/?{urlencode(params)}"


def invite_path(code: str, provider_id: int | None = None) -> str:
    path = f"/invite/{code}/"
    return f"{path}?{urlencode({'provider': provider_id})}" if provider_id else path


def unsubscribe_token(user) -> str:
    # Signed, not stored: it can't be guessed for another account and needs no table. No timestamp, so it never
    # expires and an old email's link keeps working.
    return signing.Signer(salt=_UNSUBSCRIBE_SALT).sign_object(user.pk)


def user_id_from_unsubscribe_token(token: str) -> int | None:
    try:
        value = signing.Signer(salt=_UNSUBSCRIBE_SALT).unsign_object(token)
    except (signing.BadSignature, ValueError):
        return None
    return value if isinstance(value, int) else None


def unsubscribe_path(user) -> str:
    return f"/reminders/unsubscribe/{unsubscribe_token(user)}/"
