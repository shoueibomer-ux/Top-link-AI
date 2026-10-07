"""The only module that talks to Twilio. Everything else calls send_sms() and
valid_signature(), so tests can mock Twilio in one place and the rest of the
app never imports the SDK."""

from django.conf import settings

OPTED_OUT_CODE = 21610  # Twilio: the recipient replied STOP to this number


class SmsError(Exception):
    def __init__(self, message, code=None):
        super().__init__(message)
        self.code = code


class SmsOptedOut(SmsError):
    pass


def sms_enabled() -> bool:
    return bool(settings.SMS_ENABLED)


def twilio_configured() -> bool:
    return bool(settings.TWILIO_ACCOUNT_SID and settings.TWILIO_AUTH_TOKEN and settings.TWILIO_FROM_NUMBER)


def _client():
    from twilio.rest import Client

    return Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)


def send_sms(to: str, body: str) -> str:
    """Sends one text and returns Twilio's message id. Raises SmsError (or
    SmsOptedOut) rather than ever failing silently."""
    if not sms_enabled():
        raise SmsError("SMS is turned off (SMS_ENABLED is not set to True).")
    if not twilio_configured():
        raise SmsError("Twilio is not configured: set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM_NUMBER.")

    from twilio.base.exceptions import TwilioRestException

    try:
        message = _client().messages.create(to=to, from_=settings.TWILIO_FROM_NUMBER, body=body)
    except TwilioRestException as exc:
        if exc.code == OPTED_OUT_CODE:
            raise SmsOptedOut("This number has replied STOP.", code=exc.code) from exc
        raise SmsError(f"Twilio error {exc.code}: {exc.msg}", code=exc.code) from exc
    return message.sid


def valid_signature(request) -> bool:
    """True only if Twilio really sent this request: its X-Twilio-Signature is
    an HMAC of the exact public URL and the form fields, keyed by the auth
    token. Without a configured token nothing is valid."""
    token = settings.TWILIO_AUTH_TOKEN
    signature = request.headers.get("X-Twilio-Signature", "")
    if not token or not signature:
        return False

    from twilio.request_validator import RequestValidator

    url = settings.TWILIO_WEBHOOK_URL or request.build_absolute_uri()
    return RequestValidator(token).validate(url, request.POST.dict(), signature)
