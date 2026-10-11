import re
from dataclasses import dataclass
from urllib.parse import quote

from django.db import transaction
from django.db.models import Avg, Count, Q
from django.utils import timezone

from catalog.models import Service

from . import sms
from .models import LeadOffer, Provider
from .phone import normalize_phone

MAX_OFFERS_PER_SEND = 3

URGENCY_LABELS = {
    "today": "needed today",
    "this_week": "needed this week",
    "exploring": "just exploring",
}


def service_name(service_request) -> str:
    service = Service.objects.filter(slug=service_request.category).first()
    return service.name if service else service_request.category


def urgency_label(service_request) -> str:
    return URGENCY_LABELS.get(service_request.urgency, "urgency not specified")


# ---- messages ---------------------------------------------------------------

def offer_message(offer: LeadOffer) -> str:
    """The first text to a provider: who we are, what and where, how to reply.
    Deliberately no client phone and no free-text description (which can
    contain contact details) — those come after a YES."""
    request = offer.service_request
    return (
        f"Tabmatch: new client request. {service_name(request)} in {request.city}, "
        f"{urgency_label(request)}. "
        f"Reply YES {offer.ref} to get the client's contact details, or NO {offer.ref} to pass. "
        "Reply STOP to opt out."
    )


def followup_message(offer: LeadOffer) -> str:
    """Sent only after the provider says YES."""
    request = offer.service_request
    parts = [
        f"Tabmatch: thanks! Client phone: {request.phone}.",
        f"Request: {service_name(request)} in {request.city}, {urgency_label(request)}.",
    ]
    if request.problem_description.strip():
        parts.append(f"Notes: {request.problem_description.strip()[:300]}")
    parts.append("Please contact them directly.")
    return " ".join(parts)


def reminder_message(offer: LeadOffer) -> str:
    request = offer.service_request
    return (
        f"Tabmatch reminder: the {service_name(request)} request in {request.city} is still open. "
        f"Reply YES {offer.ref} or NO {offer.ref}. Reply STOP to opt out."
    )


def sms_link(phone: str, body: str) -> str:
    return f"sms:{phone}?&body={quote(body)}"


def tel_link(phone: str) -> str:
    return f"tel:{phone}"


# ---- who can be offered a request -------------------------------------------

def forwarding_problem(service_request) -> str:
    """Why this request can't be forwarded to providers, or "" if it can."""
    if not service_request.consent_given:
        return "The client didn't consent to sharing this request."
    service = Service.objects.filter(slug=service_request.category).first()
    if service is None or not service.is_active:
        return "That service isn't active in the catalog."
    if not service.is_launched:
        return (
            f"{service.name} isn't launched yet, and the waitlist consent only covers sharing once the service "
            "is available. Set it to launched in the admin first."
        )
    return ""


@dataclass
class Candidate:
    provider: Provider
    reason: str  # "" if eligible, else why not
    already_offered: bool
    area_note: str
    accepted: int
    avg_response: object


def suggest_providers(service_request) -> list:
    """Providers offering this request's service in its city, eligible ones
    first, best past responders first among them. Providers with no service
    area set are included (flagged) rather than hidden."""
    already = set(service_request.offers.values_list("provider_id", flat=True))
    providers = (
        Provider.objects.filter(services__slug=service_request.category)
        .annotate(
            accepted=Count("offers", filter=Q(offers__status=LeadOffer.STATUS_ACCEPTED), distinct=True),
            avg_response=Avg("offers__response_time"),
        )
        .distinct()
    )
    candidates = []
    for provider in providers:
        areas = provider.service_areas or []
        if areas and service_request.city not in areas:
            continue
        candidates.append(
            Candidate(
                provider=provider,
                reason=provider.cannot_text_reason,
                already_offered=provider.pk in already,
                area_note="" if areas else "no service area set",
                accepted=provider.accepted,
                avg_response=provider.avg_response,
            )
        )
    candidates.sort(
        key=lambda c: (
            bool(c.reason or c.already_offered),
            -c.accepted,
            c.avg_response is None,
            c.avg_response,
            c.provider.business_name.lower(),
        )
    )
    return candidates


# ---- creating and sending offers ---------------------------------------------

def create_offers(service_request, providers) -> list:
    """Creates pending offers for the chosen providers, all or nothing."""
    providers = list(providers)
    if not providers:
        raise ValueError("Pick at least one provider.")
    if len(providers) > MAX_OFFERS_PER_SEND:
        raise ValueError(f"Pick at most {MAX_OFFERS_PER_SEND} providers.")
    problem = forwarding_problem(service_request)
    if problem:
        raise ValueError(problem)
    for provider in providers:
        if provider.cannot_text_reason:
            raise ValueError(f"{provider} can't be contacted: {provider.cannot_text_reason}.")
        if service_request.offers.filter(provider=provider).exists():
            raise ValueError(f"{provider} already has an offer for this request.")
    with transaction.atomic():
        return [LeadOffer.objects.create(service_request=service_request, provider=provider) for provider in providers]


def _send_and_record(offer: LeadOffer, body: str):
    try:
        return sms.send_sms(offer.provider.phone, body)
    except sms.SmsOptedOut as exc:
        Provider.objects.filter(pk=offer.provider_id).update(sms_opt_out=True)
        offer.send_error = str(exc)
        offer.save(update_fields=["send_error"])
        raise
    except sms.SmsError as exc:
        offer.send_error = str(exc)
        offer.save(update_fields=["send_error"])
        raise


def send_offer_sms(offer: LeadOffer) -> None:
    """Texts the offer through Twilio and marks it sent. On failure the offer
    stays pending with the error recorded, and SmsError is raised."""
    sid = _send_and_record(offer, offer_message(offer))
    offer.mark_sent(sid=sid)


def share_client_phone(offer: LeadOffer) -> bool:
    """The second text, with the client's phone, sent once after a YES.
    Returns False without sending if it already went out."""
    if offer.client_phone_shared_at is not None:
        return False
    sid = _send_and_record(offer, followup_message(offer))
    offer.followup_sid = sid
    offer.client_phone_shared_at = timezone.now()
    offer.save(update_fields=["followup_sid", "client_phone_shared_at"])
    return True


def mark_followup_sent(offer: LeadOffer) -> None:
    """Manual mode: you sent the client's phone yourself."""
    offer.client_phone_shared_at = timezone.now()
    offer.save(update_fields=["client_phone_shared_at"])


# ---- inbound SMS ---------------------------------------------------------------

_COMMAND = re.compile(
    r"^\s*(YES|Y|NO|N|STOP|STOPALL|UNSUBSCRIBE|CANCEL|END|QUIT)\b[\s#:.!,\-]*(\d+)?",
    re.IGNORECASE,
)
_STOP_WORDS = {"STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT"}


def parse_command(body: str):
    """("yes" | "no" | "stop", ref or None), or None if it isn't one."""
    match = _COMMAND.match(body or "")
    if not match:
        return None
    word = match.group(1).upper()
    ref = int(match.group(2)) if match.group(2) else None
    if word in _STOP_WORDS:
        return "stop", None
    return ("yes" if word in ("YES", "Y") else "no"), ref


def handle_inbound_sms(from_phone: str, body: str) -> str:
    """Applies a provider's reply. Returns text to send back in the webhook's
    response, or "" for none."""
    phone = normalize_phone(from_phone)
    providers = Provider.objects.filter(phone=phone) if phone else Provider.objects.none()
    if not providers.exists():
        return ""  # not a provider we know: ignore

    command = parse_command(body)
    awaiting = LeadOffer.objects.filter(
        provider__in=providers,
        sent_at__isnull=False,
        responded_at__isnull=True,
        status__in=[LeadOffer.STATUS_SENT, LeadOffer.STATUS_VIEWED, LeadOffer.STATUS_EXPIRED],
    ).select_related("service_request", "provider")

    if command is None:
        if awaiting.exists():
            return "Tabmatch: please reply YES <number> or NO <number>, or STOP to opt out."
        return ""

    verb, ref = command
    if verb == "stop":
        providers.update(sms_opt_out=True)
        return ""

    if ref is not None:
        offer = LeadOffer.objects.filter(pk=ref, provider__in=providers).select_related("service_request", "provider").first()
        if offer is None:
            return f"Tabmatch: we couldn't find request number {ref}."
        if not offer.awaiting_reply:
            return ""  # already answered (or never sent): a repeat changes nothing
    else:
        open_offers = list(awaiting)
        if not open_offers:
            return "Tabmatch: you have no open requests right now."
        if len(open_offers) > 1:
            refs = ", ".join(str(o.ref) for o in open_offers)
            return f"Tabmatch: you have several open requests ({refs}). Reply YES <number> or NO <number>."
        offer = open_offers[0]

    recorded = offer.record_reply(
        LeadOffer.REPLY_YES if verb == "yes" else LeadOffer.REPLY_NO, LeadOffer.CHANNEL_SMS
    )
    if recorded and verb == "yes":
        try:
            share_client_phone(offer)
        except sms.SmsError:
            pass  # recorded on the offer (send_error); the admin can follow up by hand
    return ""
