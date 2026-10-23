from django.db.models import Prefetch
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView
from rest_framework.response import Response

from accounts.permissions import IsClientAccount
from catalog.models import Service
from catalog.taxonomy import launched_slugs
from growth import attribution
from leads.models import LeadOffer
from leads.phone import normalize_north_american_phone
from matching.permissions import HasApiKey
from reviews import ratings

from .chat_service import refine_request
from .models import ProviderOnboarding, ServiceRequest
from .serializers import ProviderOnboardingSerializer, ServiceRequestSerializer
from .services import CITIES


class ChatRefineView(APIView):
    """POST /api/chat/refine/ {"message": ..., "device_id": ...}

    Free-text classification only — no request is created here (see
    ServiceRequestCreateView for that). Lets Ask AI tell the client what
    category it thinks they mean before they commit to anything; the client
    then continues into the same request flow a category tap would, with
    that category pre-selected (see OnboardingScreen's initialCategory).
    """

    def post(self, request):
        text = (request.data.get("message") or "").strip()
        device_id = request.data.get("device_id")

        if not text:
            return Response({"detail": "message is required."}, status=400)
        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)

        refined = refine_request(text)
        category = refined["category"]
        return Response({
            "category": category,
            # False when the service exists but isn't launched yet — the app
            # shows "coming soon" instead of continuing into the request flow.
            "launched": category in launched_slugs() if category else False,
            "urgency": refined["urgency"],
            "notes": refined["notes"],
        })


class ServiceRequestCreateView(APIView):
    """POST /api/requests/   (signed-in client, Authorization: Bearer ...)
    {"category", "phone", "consent": true, "device_id": (optional),
     "city": (optional), "description": (optional), "urgency": (optional),
     "source" / "source_ref": (optional, see growth.attribution)}

    The request belongs to the signed-in client: every later look at it, and
    chat and reviews, go through that account, never through device_id.

    Creates a ServiceRequest — the one thing this endpoint does, shared by
    the app's own request flow and (once it exists) the website form. No
    provider matching or routing happens here yet (see docs/ai-agent-system.md
    for where that's headed); a human currently reads these from the Django
    admin.

    `phone` must be a Canadian / North American number (10 digits, or 11
    starting with 1); it is stored as +1XXXXXXXXXX. Anything else is a 400.

    `category` must be the slug of an active catalog.Service, otherwise 400.
    If that service is not launched yet (Service.is_launched) the request is
    still saved, with status "waitlisted", and the response carries
    COMING_SOON_MESSAGE for the client to show.

    `consent` must be exactly `true` — explicit, per-request, opt-in consent
    to share the request (including the phone number) with providers. There
    is no default or inferred consent; a request without it is rejected, not
    silently created without sharing.
    """

    COMING_SOON_MESSAGE = (
        "This service is coming soon in your area. We saved your request and "
        "will contact you when it opens."
    )
    INVALID_PHONE_MESSAGE = "Enter a valid Canadian or North American phone number, for example 780 555 0100."
    REQUIRED_CONSENT_MESSAGE = (
        "You must consent to share your request details, including your phone "
        "number, with service providers before submitting a request."
    )

    permission_classes = [HasApiKey, IsAuthenticated, IsClientAccount]

    def post(self, request):
        device_id = request.data.get("device_id")
        device_id = device_id[:64] if isinstance(device_id, str) else ""
        category = request.data.get("category")
        raw_phone = request.data.get("phone")
        city = request.data.get("city") or "Edmonton"
        description = (request.data.get("description") or "").strip()
        location = request.data.get("location") or ""
        if not isinstance(location, str):
            return Response({"detail": "location must be text."}, status=400)
        location = " ".join(location.split())
        if len(location) > 120:
            return Response({"detail": "location is too long (120 characters at most)."}, status=400)
        urgency = request.data.get("urgency") or ""
        if not isinstance(urgency, str) or urgency not in dict(ServiceRequest.URGENCY_CHOICES):
            urgency = ""

        if not category:
            return Response({"detail": "category is required."}, status=400)
        service = (
            Service.objects.filter(slug=category, is_active=True, category__is_active=True).first()
            if isinstance(category, str)
            else None
        )
        if service is None:
            return Response({"detail": "category must be an active service."}, status=400)
        if raw_phone is None or (isinstance(raw_phone, str) and not raw_phone.strip()):
            return Response({"detail": "phone is required."}, status=400)
        phone = normalize_north_american_phone(raw_phone)
        if not phone:
            return Response({"detail": self.INVALID_PHONE_MESSAGE}, status=400)
        if city not in CITIES:
            return Response({"detail": f"city must be one of {CITIES}."}, status=400)
        if request.data.get("consent") is not True:
            return Response({"detail": self.REQUIRED_CONSENT_MESSAGE}, status=400)

        source, source_ref = attribution.resolve(request.user, request.data.get("source"), request.data.get("source_ref"))
        service_request = ServiceRequest.objects.create(
            source=source,
            source_ref=source_ref,
            user=request.user,
            device_id=device_id,
            category=service.slug,
            city=city,
            location=location,
            problem_description=description,
            phone=phone,
            consent_given=True,
            urgency=urgency,
            status=ServiceRequest.STATUS_NEW if service.is_launched else ServiceRequest.STATUS_WAITLISTED,
        )
        body = {
            "request_id": service_request.id,
            "category": service_request.category,
            "status": service_request.status,
            "urgency": urgency,
        }
        if service_request.status == ServiceRequest.STATUS_WAITLISTED:
            body["message"] = self.COMING_SOON_MESSAGE
        return Response(body, status=201)


def _with_accepted_offers(queryset):
    return queryset.prefetch_related(
        Prefetch(
            "offers",
            queryset=LeadOffer.objects.filter(status=LeadOffer.STATUS_ACCEPTED).select_related("provider", "review__client__profile"),
            to_attr="accepted_offers_cache",
        )
    )


class ServiceRequestListView(APIView):
    """GET /api/requests/mine/   (signed-in client): "Your requests", every
    request this account submitted, newest first, with the providers who
    accepted it.

    This used to list by an unauthenticated device_id, which made a phone
    number readable to whoever held that id. It now needs sign-in, and a
    device_id in the URL is ignored."""

    permission_classes = [HasApiKey, IsAuthenticated, IsClientAccount]

    def get(self, request):
        requests = list(_with_accepted_offers(ServiceRequest.objects.filter(user=request.user)).order_by("-created_at"))
        provider_ids = [o.provider_id for r in requests for o in r.accepted_offers_cache]
        context = {"provider_ratings": ratings.summaries(provider_ids)}
        return Response({"requests": ServiceRequestSerializer(requests, many=True, context=context).data})


class ServiceRequestCompleteView(APIView):
    """POST /api/requests/<id>/complete/ {"offer_id": N}   (signed-in client)

    The client says the job with one provider who accepted is done: that offer
    becomes hired and completed. Only the request's own client can do this
    (anyone else gets a 404), only for an accepted offer of that request, and
    only once per request. An admin can still tick it in the admin.
    """

    permission_classes = [HasApiKey, IsAuthenticated, IsClientAccount]

    def post(self, request, request_id):
        service_request = ServiceRequest.objects.filter(pk=request_id, user=request.user).first()
        if service_request is None:
            return Response({"detail": "Request not found."}, status=404)
        offer_id = request.data.get("offer_id")
        offer = (
            service_request.offers.filter(pk=offer_id, status=LeadOffer.STATUS_ACCEPTED).first()
            if isinstance(offer_id, int) and not isinstance(offer_id, bool)
            else None
        )
        if offer is None:
            return Response({"detail": "That provider has not accepted this request."}, status=400)
        if service_request.offers.filter(job_completed=True).exists():
            return Response({"detail": "This request is already marked completed."}, status=409)
        offer.hired = True
        offer.job_completed = True
        offer.save()
        refreshed = _with_accepted_offers(ServiceRequest.objects.filter(pk=service_request.pk)).get()
        return Response(ServiceRequestSerializer(refreshed).data)


class ProviderOnboardingView(APIView):
    """GET/POST /api/provider-onboarding/?provider_id=

    Structured provider sign-up, tracked as 5 independent sections
    (personal_info, services, service_area, credentials, photos) so a
    provider can complete them in any order across sessions —
    completion_percentage (see ProviderOnboarding) is what flags an
    incomplete profile for follow-up. `provider_id` is a self-issued
    identifier (see lib/provider/provider_id.dart), the same pattern as
    device_id.
    """

    def get(self, request):
        provider_id = request.query_params.get("provider_id")
        if not provider_id:
            return Response({"detail": "provider_id is required."}, status=400)
        onboarding, _ = ProviderOnboarding.objects.get_or_create(provider_id=provider_id)
        return Response(ProviderOnboardingSerializer(onboarding).data)

    def post(self, request):
        provider_id = request.data.get("provider_id")
        section = request.data.get("section")
        fields = request.data.get("fields")

        if not provider_id:
            return Response({"detail": "provider_id is required."}, status=400)
        if section not in ProviderOnboarding.SECTION_FIELDS:
            return Response(
                {"detail": f"section must be one of {sorted(ProviderOnboarding.SECTION_FIELDS)}."}, status=400
            )
        if not isinstance(fields, dict):
            return Response({"detail": "fields must be an object."}, status=400)

        onboarding, _ = ProviderOnboarding.objects.get_or_create(provider_id=provider_id)
        allowed = set(ProviderOnboarding.SECTION_FIELDS[section])
        changed = []
        for key, value in fields.items():
            if key not in allowed:
                continue
            setattr(onboarding, key, value)
            changed.append(key)

        if changed:
            onboarding.save(update_fields=[*changed, "updated_at"])
        return Response(ProviderOnboardingSerializer(onboarding).data)
