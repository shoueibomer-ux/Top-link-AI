from rest_framework import serializers

from leads.models import LeadOffer
from reviews import ratings
from reviews.serializers import serialize_review

from .models import ProviderOnboarding, ServiceRequest


class ServiceRequestSerializer(serializers.ModelSerializer):
    """The signed-in client's own view of a request they submitted: see
    ServiceRequestListView ("Your requests"). Includes `phone` (it's their
    own number) and omits `consent_given` (it's always true for any row that
    exists, see ServiceRequestCreateView, so showing it back adds nothing).

    `accepted_offers` are the providers who said YES, with what the client may
    do next: only an accepted offer can be marked completed, and only once per
    request.
    """

    accepted_offers = serializers.SerializerMethodField()

    class Meta:
        model = ServiceRequest
        fields = [
            "id",
            "category",
            "city",
            "problem_description",
            "phone",
            "status",
            "urgency",
            "created_at",
            "accepted_offers",
        ]

    def get_accepted_offers(self, obj):
        offers = getattr(obj, "accepted_offers_cache", None)
        if offers is None:
            offers = list(obj.offers.filter(status=LeadOffer.STATUS_ACCEPTED).select_related("provider", "review__client__profile"))
        completed = any(o.job_completed for o in offers)
        known = self.context.get("provider_ratings")
        summaries = known if known is not None else ratings.summaries([o.provider_id for o in offers])
        return [
            {
                "offer_id": o.id,
                "provider": {"id": o.provider_id, "business_name": o.provider.business_name, **summaries.get(o.provider_id, ratings.EMPTY)},
                "accepted_at": o.responded_at,
                "hired": o.hired,
                "job_completed": o.job_completed,
                "completed_at": o.completed_at,
                "can_complete": not completed,
                "review": self._review_of(o, obj.user_id),
                "can_review": o.job_completed and not hasattr(o, "review"),
            }
            for o in offers
        ]

    @staticmethod
    def _review_of(offer, owner_id):
        review = getattr(offer, "review", None)
        return serialize_review(review, owner_id) if review is not None else None


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
