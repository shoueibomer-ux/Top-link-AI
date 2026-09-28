import re

from rest_framework import serializers

from .models import ProviderMatch, ProviderOnboarding


def mask_phone(phone: str) -> str:
    """Keeps everything except the final run of digits, e.g.
    "+1 780-904-1234" -> "+1 780-904-XXXX". Used for every provider that
    isn't unlocked for the requesting device — see RealProviderSerializer.
    """
    if not phone:
        return ""
    return re.sub(r"\d+(?!.*\d)", lambda m: "X" * len(m.group()), phone)


class RealProviderSerializer(serializers.Serializer):
    """A single Google Places search result, masked or full depending on
    whether `context["unlocked_place_ids"]` (built server-side from real
    ProviderMatch rows — see provider_search.views) contains this provider's
    place_id. This is the ONLY place that decides whether a client gets a
    real phone number/address/website — never the Flutter UI, so an
    unauthorized client can't just read the field straight off the wire
    before payment/subscription is verified.

    Free/always visible: name, rating, rating_count, city, place_id,
    recent_contact_count, is_available_now, estimated_response_minutes.
    Gated behind `is_unlocked`: phone (full vs masked), address (full vs
    omitted — only `city` is shown pre-unlock), website, maps_url.
    """

    place_id = serializers.CharField()
    name = serializers.CharField()
    city = serializers.CharField()
    rating = serializers.FloatField(allow_null=True)
    rating_count = serializers.IntegerField(allow_null=True)
    recent_contact_count = serializers.IntegerField(default=0)
    is_available_now = serializers.BooleanField(default=True)
    estimated_response_minutes = serializers.IntegerField(allow_null=True, required=False)
    is_unlocked = serializers.SerializerMethodField()
    phone = serializers.SerializerMethodField()
    address = serializers.SerializerMethodField()
    website = serializers.SerializerMethodField()
    maps_url = serializers.SerializerMethodField()

    def _unlocked(self, obj) -> bool:
        unlocked_place_ids = self.context.get("unlocked_place_ids") or set()
        return obj.get("place_id") in unlocked_place_ids

    def get_is_unlocked(self, obj) -> bool:
        return self._unlocked(obj)

    def get_phone(self, obj) -> str:
        phone = obj.get("phone") or ""
        return phone if self._unlocked(obj) else mask_phone(phone)

    def get_address(self, obj) -> str | None:
        return obj.get("address") or None if self._unlocked(obj) else None

    def get_website(self, obj) -> str | None:
        return (obj.get("website") or None) if self._unlocked(obj) else None

    def get_maps_url(self, obj) -> str | None:
        return (obj.get("maps_url") or None) if self._unlocked(obj) else None


class ProviderMatchSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProviderMatch
        fields = [
            "id",
            "category",
            "city",
            "provider_name",
            "provider_phone",
            "provider_address",
            "provider_website",
            "problem_description",
            "status",
            "unlock_method",
            "provider_decision",
            "provider_message",
            "responded_at",
            "first_unlocked_at",
            "last_viewed_at",
        ]


class ProviderOnboardingSerializer(serializers.ModelSerializer):
    completion_percentage = serializers.ReadOnlyField()
    is_complete = serializers.ReadOnlyField()
    section_status = serializers.SerializerMethodField()

    class Meta:
        model = ProviderOnboarding
        fields = [
            "provider_id",
            "full_name",
            "phone",
            "email",
            "services",
            "city",
            "years_experience",
            "is_insured",
            "photo_urls",
            "completion_percentage",
            "is_complete",
            "section_status",
            "updated_at",
        ]

    def get_section_status(self, obj: ProviderOnboarding) -> dict:
        return {section: obj.section_complete(section) for section in obj.SECTION_FIELDS}
