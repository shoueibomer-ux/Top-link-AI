from rest_framework import serializers

from .models import ProviderMatch, ProviderOnboarding


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
