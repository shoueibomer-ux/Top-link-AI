from rest_framework.views import APIView
from rest_framework.response import Response

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
        return Response({
            "category": refined["category"],
            "urgency": refined["urgency"],
            "notes": refined["notes"],
        })


class ServiceRequestCreateView(APIView):
    """POST /api/requests/
    {"device_id", "category", "phone", "consent": true,
     "city": (optional), "description": (optional), "urgency": (optional)}

    Creates a ServiceRequest — the one thing this endpoint does, shared by
    the app's own request flow and (once it exists) the website form. No
    provider matching or routing happens here yet (see docs/ai-agent-system.md
    for where that's headed); a human currently reads these from the Django
    admin.

    `consent` must be exactly `true` — explicit, per-request, opt-in consent
    to share the request (including the phone number) with providers. There
    is no default or inferred consent; a request without it is rejected, not
    silently created without sharing.
    """

    REQUIRED_CONSENT_MESSAGE = (
        "You must consent to share your request details, including your phone "
        "number, with service providers before submitting a request."
    )

    def post(self, request):
        device_id = request.data.get("device_id")
        category = request.data.get("category")
        phone = (request.data.get("phone") or "").strip()
        city = request.data.get("city") or "Edmonton"
        description = (request.data.get("description") or "").strip()
        urgency = request.data.get("urgency") or ""

        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)
        if not category:
            return Response({"detail": "category is required."}, status=400)
        if not phone:
            return Response({"detail": "phone is required."}, status=400)
        if city not in CITIES:
            return Response({"detail": f"city must be one of {CITIES}."}, status=400)
        if request.data.get("consent") is not True:
            return Response({"detail": self.REQUIRED_CONSENT_MESSAGE}, status=400)

        service_request = ServiceRequest.objects.create(
            device_id=device_id,
            category=category,
            city=city,
            problem_description=description,
            phone=phone,
            consent_given=True,
        )
        return Response(
            {
                "request_id": service_request.id,
                "category": service_request.category,
                "urgency": urgency,
            },
            status=201,
        )


class ServiceRequestListView(APIView):
    """GET /api/requests/?device_id=...  — "Your requests": every request
    this device has submitted, newest first."""

    def get(self, request):
        device_id = request.query_params.get("device_id")
        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)

        requests = ServiceRequest.objects.filter(device_id=device_id).order_by("-created_at")
        return Response({"requests": ServiceRequestSerializer(requests, many=True).data})


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
