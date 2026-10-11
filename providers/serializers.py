from rest_framework import serializers

from catalog.models import Service
from leads.phone import normalize_north_american_phone
from provider_search.services import CITIES

from .models import ProviderProfile

INVALID_PHONE_MESSAGE = "Enter a valid Canadian or North American phone number, for example 780 555 0100."


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

    class Meta:
        model = ProviderProfile
        fields = [
            "business_name", "phone", "email", "categories", "cities", "bio",
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


class PublicProviderSerializer(serializers.ModelSerializer):
    """What a client may see of an approved provider: no phone, no email."""

    categories = serializers.SlugRelatedField(many=True, read_only=True, slug_field="slug")

    class Meta:
        model = ProviderProfile
        fields = ["id", "business_name", "bio", "categories", "cities"]
