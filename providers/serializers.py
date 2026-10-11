from django.utils import timezone
from rest_framework import serializers

from catalog.models import Service
from leads.phone import normalize_north_american_phone
from provider_search.services import CITIES

from .models import ProviderProfile

INVALID_PHONE_MESSAGE = "Enter a valid Canadian or North American phone number, for example 780 555 0100."
SMS_CONSENT_MESSAGE = "You must agree to be texted about client requests to register."


class ProviderProfileSerializer(serializers.ModelSerializer):
    """What a provider sends and sees about their own profile. `categories`
    are catalog.Service slugs (any active service, launched or not, so
    providers can sign up for upcoming ones). Status, the review note and
    the review time are only ever set by an admin."""

    categories = serializers.SlugRelatedField(
        many=True,
        allow_empty=False,
        slug_field="slug",
        queryset=Service.objects.filter(is_active=True, category__is_active=True),
    )
    cities = serializers.ListField(child=serializers.ChoiceField(choices=CITIES), allow_empty=False)
    email = serializers.EmailField(required=False)
    bio = serializers.CharField(max_length=1000, required=False, allow_blank=True)
    # The explicit CASL consent checkbox. Required (and must be true) when
    # registering; only the time it was given is stored, and it can't be
    # changed by editing the profile afterwards.
    sms_consent = serializers.BooleanField(write_only=True, required=False)

    class Meta:
        model = ProviderProfile
        fields = [
            "business_name", "phone", "email", "categories", "cities", "bio", "sms_consent",
            "status", "review_note", "reviewed_at", "created_at",
        ]
        read_only_fields = ["status", "review_note", "reviewed_at", "created_at"]

    def validate_business_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Enter your business name.")
        return value

    def validate_phone(self, value):
        phone = normalize_north_american_phone(value)
        if not phone:
            raise serializers.ValidationError(INVALID_PHONE_MESSAGE)
        return phone

    def validate_cities(self, value):
        return list(dict.fromkeys(value))  # no repeats, order kept

    def validate(self, attrs):
        if self.instance is None and attrs.get("sms_consent") is not True:
            raise serializers.ValidationError({"sms_consent": SMS_CONSENT_MESSAGE})
        return attrs

    def create(self, validated_data):
        validated_data.pop("sms_consent", None)
        return super().create({**validated_data, "sms_consent_at": timezone.now()})

    def update(self, instance, validated_data):
        validated_data.pop("sms_consent", None)
        return super().update(instance, validated_data)


class PublicProviderSerializer(serializers.ModelSerializer):
    """What a client may see of an approved provider: no phone, no email."""

    categories = serializers.SlugRelatedField(many=True, read_only=True, slug_field="slug")

    class Meta:
        model = ProviderProfile
        fields = ["id", "business_name", "bio", "categories", "cities"]
