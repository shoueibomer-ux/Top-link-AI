from django.contrib import admin
from django.urls import include, path

from notifications.views import NotificationListView, NotificationMarkReadView
from provider_search.views import (
    ChatRefineView,
    ProviderOnboardingView,
    ServiceRequestCreateView,
    ServiceRequestListView,
)

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/accounts/", include("accounts.urls")),
    path("api/catalog/", include("catalog.urls")),
    path("api/", include("matching.urls")),
    path("api/requests/", ServiceRequestCreateView.as_view(), name="service-request-create"),
    path("api/requests/mine/", ServiceRequestListView.as_view(), name="service-request-list"),
    path("api/provider-onboarding/", ProviderOnboardingView.as_view(), name="provider-onboarding"),
    path("api/chat/refine/", ChatRefineView.as_view(), name="chat-refine"),
    path("api/notifications/", NotificationListView.as_view(), name="notification-list"),
    path("api/notifications/mark-read/", NotificationMarkReadView.as_view(), name="notification-mark-read"),
    # Marketing website — keep last so admin/ and api/ always take precedence.
    path("", include("website.urls")),
]

# Branded 404 for the website; unmatched /api/ paths still get JSON.
handler404 = "website.views.not_found"
