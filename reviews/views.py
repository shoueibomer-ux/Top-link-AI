from django.db import IntegrityError, transaction
from django.db.models import Q
from django.utils import timezone
from django.utils.decorators import method_decorator
from django_ratelimit.decorators import ratelimit
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import UserRole
from accounts.permissions import IsClientAccount
from leads.models import LeadOffer
from matching.permissions import HasApiKey
from providers.models import ProviderProfile

from . import ratings
from .models import MAX_COMMENT_CHARS, Favorite, Review, ReviewReport
from .serializers import provider_card, serialize_review

_WRITE_RATE = "30/h"
MAX_REPLY_CHARS = 1000
PAGE_SIZE = 50


class IsProviderAccount(BasePermission):
    message = "Only provider accounts can do this."

    def has_permission(self, request, view):
        profile = getattr(request.user, "profile", None)
        return bool(profile and profile.role == UserRole.PROVIDER)


class ReviewView(APIView):
    """Reviews need the API key and a signed-in person; what each person may do is decided per review."""

    permission_classes = [HasApiKey, IsAuthenticated]


def _not_found(what="Review"):
    return Response({"detail": f"{what} not found."}, status=404)


def _clean_text(value, limit):
    """(text, error): a string trimmed to nothing-or-text, or an error message when it is the wrong type/too long."""
    if value is None:
        return "", None
    if not isinstance(value, str):
        return "", "Enter text."
    value = value.strip()
    if len(value) > limit:
        return "", f"Keep it to {limit} characters or fewer."
    return value, None


def _parse_rating(value):
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        return None
    try:
        rating = int(value)
    except ValueError:
        return None
    return rating if 1 <= rating <= 5 else None


def _client_offer(user, offer_id):
    """The offer, but only for the client who owns its request."""
    return (
        LeadOffer.objects.filter(pk=offer_id, service_request__user=user)
        .select_related("provider", "service_request")
        .first()
    )


class OfferReviewView(ReviewView):
    """/api/offers/<offer_id>/review/   (the client who owns the request)

    GET returns their review of this job (404 if none yet), POST writes it (once, only after the job is marked
    complete), PATCH changes it for 7 days after it was posted."""

    permission_classes = [HasApiKey, IsAuthenticated, IsClientAccount]

    def get(self, request, offer_id):
        offer = _client_offer(request.user, offer_id)
        review = Review.objects.filter(offer=offer).select_related("client__profile").first() if offer else None
        if review is None:
            return _not_found()
        return Response(serialize_review(review, request.user.pk))

    @method_decorator(ratelimit(key="user_or_ip", rate=_WRITE_RATE, method=["POST", "PATCH"], block=False))
    def post(self, request, offer_id):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many requests. Try again later."}, status=429)
        offer = _client_offer(request.user, offer_id)
        if offer is None:
            return _not_found("Job")
        if not offer.job_completed:
            return Response({"detail": "You can review a provider after the job is marked complete."}, status=400)
        rating = _parse_rating(request.data.get("rating"))
        if rating is None:
            return Response({"detail": "Choose a rating from 1 to 5 stars."}, status=400)
        comment, error = _clean_text(request.data.get("comment"), MAX_COMMENT_CHARS)
        if error:
            return Response({"detail": error}, status=400)
        try:
            with transaction.atomic():
                review = Review.objects.create(
                    offer=offer, client=request.user, provider=offer.provider, rating=rating, comment=comment
                )
        except IntegrityError:
            return Response({"detail": "You have already reviewed this job."}, status=409)
        return Response(serialize_review(review, request.user.pk), status=201)

    @method_decorator(ratelimit(key="user_or_ip", rate=_WRITE_RATE, method=["POST", "PATCH"], block=False))
    def patch(self, request, offer_id):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many requests. Try again later."}, status=429)
        offer = _client_offer(request.user, offer_id)
        review = Review.objects.filter(offer=offer).first() if offer else None
        if review is None:
            return _not_found()
        if review.hidden:
            return Response({"detail": "This review was removed and can't be changed."}, status=403)
        if not review.can_be_edited():
            return Response({"detail": "Reviews can only be changed for 7 days after you post them."}, status=403)
        changed = False
        if "rating" in request.data:
            rating = _parse_rating(request.data.get("rating"))
            if rating is None:
                return Response({"detail": "Choose a rating from 1 to 5 stars."}, status=400)
            review.rating = rating
            changed = True
        if "comment" in request.data:
            comment, error = _clean_text(request.data.get("comment"), MAX_COMMENT_CHARS)
            if error:
                return Response({"detail": error}, status=400)
            review.comment = comment
            changed = True
        if changed:
            review.edited_at = timezone.now()
            review.save(update_fields=["rating", "comment", "edited_at", "updated_at"])
        return Response(serialize_review(review, request.user.pk))


class ReviewReplyView(ReviewView):
    """POST /api/reviews/<id>/reply/ {"text"}   (the reviewed provider)

    One public reply per review. It can't be edited or removed by the provider afterwards (staff can clear it)."""

    permission_classes = [HasApiKey, IsAuthenticated, IsProviderAccount]

    @method_decorator(ratelimit(key="user_or_ip", rate=_WRITE_RATE, method="POST", block=False))
    def post(self, request, review_id):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many requests. Try again later."}, status=429)
        with transaction.atomic():
            review = (
                Review.objects.select_for_update()
                .filter(pk=review_id, provider__user=request.user, hidden=False)
                .first()
            )
            if review is None:
                return _not_found()
            if review.reply:
                return Response({"detail": "You have already replied to this review."}, status=409)
            text, error = _clean_text(request.data.get("text"), MAX_REPLY_CHARS)
            if error:
                return Response({"detail": error}, status=400)
            if not text:
                return Response({"detail": "Write a reply first."}, status=400)
            review.reply = text
            review.reply_at = timezone.now()
            review.save(update_fields=["reply", "reply_at", "updated_at"])
        return Response(serialize_review(review, request.user.pk), status=201)


class ReviewReportView(ReviewView):
    """POST /api/reviews/<id>/report/ {"reason", "details"?}   (any signed-in person but the author)

    A reported review stays up until staff look at it; staff can hide it from the admin."""

    @method_decorator(ratelimit(key="user_or_ip", rate=_WRITE_RATE, method="POST", block=False))
    def post(self, request, review_id):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many requests. Try again later."}, status=429)
        review = Review.objects.filter(pk=review_id, hidden=False).first()
        if review is None:
            return _not_found()
        if review.client_id == request.user.pk:
            return Response({"detail": "You can't report your own review."}, status=400)
        reason = request.data.get("reason")
        if reason not in dict(ReviewReport.REASON_CHOICES):
            return Response({"detail": "Choose a reason."}, status=400)
        details, error = _clean_text(request.data.get("details"), 500)
        if error:
            return Response({"detail": error}, status=400)
        ReviewReport.objects.get_or_create(
            review=review, reporter=request.user, defaults={"reason": reason, "details": details}
        )
        return Response({"reported": True}, status=201)


def _visible_reviews(provider):
    return provider.reviews.filter(hidden=False).select_related("client__profile")


class ProviderReviewsView(ReviewView):
    """GET /api/providers/<id>/reviews/   (any signed-in person; approved providers only)

    The provider's public page: their details, average rating and count, and reviews newest first. A client also
    learns whether they have saved this provider."""

    def get(self, request, provider_id):
        provider = ProviderProfile.objects.approved().filter(pk=provider_id).prefetch_related("categories").first()
        if provider is None:
            return _not_found("Provider")
        reviews = list(_visible_reviews(provider)[:PAGE_SIZE])
        data = {
            "provider": provider_card(provider),
            "reviews": [serialize_review(r, request.user.pk) for r in reviews],
            "is_favorite": Favorite.objects.filter(user=request.user, provider=provider).exists(),
        }
        return Response(data)


class MyProviderReviewsView(ReviewView):
    """GET /api/provider/reviews/   (the signed-in provider): their own rating and reviews, with which still
    need a reply."""

    permission_classes = [HasApiKey, IsAuthenticated, IsProviderAccount]

    def get(self, request):
        provider = ProviderProfile.objects.filter(user=request.user).first()
        if provider is None:
            return Response({"detail": "You haven't registered a provider profile yet."}, status=404)
        reviews = list(_visible_reviews(provider)[:PAGE_SIZE])
        return Response({
            "summary": ratings.summary_for(provider.id),
            "reviews": [serialize_review(r, request.user.pk) for r in reviews],
        })


class FavoritesView(ReviewView):
    """GET /api/favorites/   (signed-in client): the providers they saved. Providers who are no longer approved
    drop out of the list (they stay saved, and return if approved again)."""

    permission_classes = [HasApiKey, IsAuthenticated, IsClientAccount]

    def get(self, request):
        favorites = list(
            Favorite.objects.filter(user=request.user, provider__status=ProviderProfile.STATUS_APPROVED)
            .select_related("provider")
            .prefetch_related("provider__categories")
        )
        summaries = ratings.summaries([f.provider_id for f in favorites])
        return Response({"favorites": [provider_card(f.provider, summaries[f.provider_id]) for f in favorites]})


class FavoriteView(ReviewView):
    """PUT /api/favorites/<provider_id>/ saves a provider, DELETE removes them; both are safe to repeat."""

    permission_classes = [HasApiKey, IsAuthenticated, IsClientAccount]

    def put(self, request, provider_id):
        provider = ProviderProfile.objects.approved().filter(pk=provider_id).first()
        if provider is None:
            return _not_found("Provider")
        Favorite.objects.get_or_create(user=request.user, provider=provider)
        return Response({"is_favorite": True})

    def delete(self, request, provider_id):
        Favorite.objects.filter(user=request.user, provider_id=provider_id).delete()
        return Response({"is_favorite": False})
