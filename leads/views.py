from xml.sax.saxutils import escape

from django.http import HttpResponse, HttpResponseForbidden
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST

from . import services, sms


def _twiml(message: str = "") -> HttpResponse:
    inner = f"<Message>{escape(message)}</Message>" if message else ""
    return HttpResponse(
        f'<?xml version="1.0" encoding="UTF-8"?><Response>{inner}</Response>',
        content_type="text/xml",
    )


@csrf_exempt
@require_POST
def twilio_sms_webhook(request):
    """POST /api/twilio/sms/ — Twilio's "a message comes in" webhook.

    A plain Django view on purpose: Twilio can't send our X-API-Key, so the
    API's default permission would reject it. The gate here is Twilio's
    request signature, checked before anything is read from the body.
    """
    if not sms.sms_enabled():
        return HttpResponseForbidden("SMS is turned off.")
    if not sms.valid_signature(request):
        return HttpResponseForbidden("Invalid signature.")
    reply = services.handle_inbound_sms(request.POST.get("From", ""), request.POST.get("Body", ""))
    return _twiml(reply)
