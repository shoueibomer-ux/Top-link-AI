from django.contrib import admin
from django.urls import include, path

from notifications.views import NotificationListView, NotificationMarkReadView
from provider_search.views import (
    ChatRefineView,
    KnownProvidersView,
    ProviderAvailabilityView,
    ProviderMatchListView,
    ProviderMatchStatusView,
    ProviderOnboardingView,
    ProviderSearchView,
)

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/accounts/", include("accounts.urls")),
    path("api/", include("matching.urls")),
    path("api/providers/search/", ProviderSearchView.as_view(), name="provider-search"),
    path("api/providers/known/", KnownProvidersView.as_view(), name="providers-known"),
    path("api/provider-matches/", ProviderMatchListView.as_view(), name="provider-match-list"),
    path("api/provider-matches/<int:pk>/status/", ProviderMatchStatusView.as_view(), name="provider-match-status"),
    path("api/provider-availability/", ProviderAvailabilityView.as_view(), name="provider-availability"),
    path("api/provider-onboarding/", ProviderOnboardingView.as_view(), name="provider-onboarding"),
    path("api/chat/refine/", ChatRefineView.as_view(), name="chat-refine"),
    path("api/notifications/", NotificationListView.as_view(), name="notification-list"),
    path("api/notifications/mark-read/", NotificationMarkReadView.as_view(), name="notification-mark-read"),
]
