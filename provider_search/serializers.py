from rest_framework import serializers

from .models import ProviderOnboarding, ServiceRequest


class ServiceRequestSerializer(serializers.ModelSerializer):
    """The client's own view of a request they submitted — see
    ServiceRequestListView ("Your requests"). Includes `phone` (it's their
    own number) and omits `consent_given` (it's always true for any row that
    exists — see ServiceRequestCreateView — so showing it back adds nothing).
    """

    class Meta:
        model = ServiceRequest
        fields = [
            "id",
            "category",
            "city",
            "problem_description",
            "phone",
            "status",
            "created_at",
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
