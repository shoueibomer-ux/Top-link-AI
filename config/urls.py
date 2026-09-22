from django.contrib import admin
from django.urls import include, path

from notifications.views import NotificationListView, NotificationMarkReadView
from provider_search.views import (
    ChatRefineView,
    KnownProvidersView,
    ProviderAvailabilityView,
    ProviderIncomingRequestListView,
    ProviderMatchListView,
    ProviderMatchStatusView,
    ProviderOnboardingView,
    ProviderRequestRespondView,
    ProviderSearchView,
    ProviderUnlockView,
)

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/accounts/", include("accounts.urls")),
    path("api/catalog/", include("catalog.urls")),
    path("api/", include("matching.urls")),
    path("api/providers/search/", ProviderSearchView.as_view(), name="provider-search"),
    path("api/providers/unlock/", ProviderUnlockView.as_view(), name="provider-unlock"),
    path("api/providers/known/", KnownProvidersView.as_view(), name="providers-known"),
    path("api/provider-matches/", ProviderMatchListView.as_view(), name="provider-match-list"),
    path("api/provider-matches/<int:pk>/status/", ProviderMatchStatusView.as_view(), name="provider-match-status"),
    path("api/provider/requests/", ProviderIncomingRequestListView.as_view(), name="provider-incoming-requests"),
    path(
        "api/provider/requests/<int:pk>/respond/",
        ProviderRequestRespondView.as_view(),
        name="provider-request-respond",
    ),
    path("api/provider-availability/", ProviderAvailabilityView.as_view(), name="provider-availability"),
    path("api/provider-onboarding/", ProviderOnboardingView.as_view(), name="provider-onboarding"),
    path("api/chat/refine/", ChatRefineView.as_view(), name="chat-refine"),
    path("api/notifications/", NotificationListView.as_view(), name="notification-list"),
    path("api/notifications/mark-read/", NotificationMarkReadView.as_view(), name="notification-mark-read"),
    # Marketing website — keep last so admin/ and api/ always take precedence.
    path("", include("website.urls")),
]

# Branded 404 for the website; unmatched /api/ paths still get JSON.
handler404 = "website.views.not_found"
