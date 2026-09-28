from django.urls import path
from .views import (
    ProfileCreateView, MatchView, CategoryProvidersView,
    SubscriptionStatusView, SubscriptionActivateView, UnlockCreditActivateView,
    CategorySuggestView,
)

urlpatterns = [
    path("profiles/", ProfileCreateView.as_view(), name="profile-create"),
    path("match/", MatchView.as_view(), name="match"),
    path("providers/", CategoryProvidersView.as_view(), name="category-providers"),
    path("categories/suggest/", CategorySuggestView.as_view(), name="category-suggest"),
    path("subscription/", SubscriptionStatusView.as_view(), name="subscription-status"),
    path("subscription/activate/", SubscriptionActivateView.as_view(), name="subscription-activate"),
    path("unlock-credits/activate/", UnlockCreditActivateView.as_view(), name="unlock-credit-activate"),
]
