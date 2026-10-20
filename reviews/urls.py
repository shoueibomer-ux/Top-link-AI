from django.urls import path

from .views import (
    FavoriteView,
    FavoritesView,
    MyProviderReviewsView,
    OfferReviewView,
    ProviderReviewsView,
    ReviewReplyView,
    ReviewReportView,
)

urlpatterns = [
    path("offers/<int:offer_id>/review/", OfferReviewView.as_view(), name="offer-review"),
    path("reviews/<int:review_id>/reply/", ReviewReplyView.as_view(), name="review-reply"),
    path("reviews/<int:review_id>/report/", ReviewReportView.as_view(), name="review-report"),
    path("providers/<int:provider_id>/reviews/", ProviderReviewsView.as_view(), name="provider-reviews"),
    path("provider/reviews/", MyProviderReviewsView.as_view(), name="my-provider-reviews"),
    path("favorites/", FavoritesView.as_view(), name="favorites"),
    path("favorites/<int:provider_id>/", FavoriteView.as_view(), name="favorite"),
]
