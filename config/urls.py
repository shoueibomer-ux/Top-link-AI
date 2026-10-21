from django.conf import settings
from django.contrib import admin
from django.http import HttpResponse
from django.urls import include, path

from config.admin_login import admin_login
from config.client_ip import client_ip

from leads.views import twilio_sms_webhook
from notifications.views import NotificationListView, NotificationMarkReadView
from provider_search.views import (
    ChatRefineView,
    ProviderOnboardingView,
    ServiceRequestCompleteView,
    ServiceRequestCreateView,
    ServiceRequestListView,
)

admin.site.site_header = "Tabmatch administration"
admin.site.site_title = "Tabmatch admin"


def client_ip_check(request):
    """Staff only: what the rate limiter sees as this request's client IP,
    next to the raw proxy values, to confirm after a deploy that it is your
    own public address (compare with any "what is my IP" site)."""
    lines = [
        f"Rate limits key on:  {client_ip(request)}",
        f"REMOTE_ADDR:         {request.META.get('REMOTE_ADDR', '')}",
        f"X-Forwarded-For:     {request.META.get('HTTP_X_FORWARDED_FOR', '(none)')}",
        f"TRUSTED_PROXY_HOPS:  {settings.TRUSTED_PROXY_HOPS}",
    ]
    return HttpResponse("\n".join(lines) + "\n", content_type="text/plain")


urlpatterns = [
    # The admin lives at ADMIN_URL_PATH (see config/settings.py). Its login
    # form is answered by the rate-limited view first, which then hands off
    # to the admin's own login.
    path(f"{settings.ADMIN_URL_PATH}login/", admin_login),
    path(f"{settings.ADMIN_URL_PATH}client-ip/", admin.site.admin_view(client_ip_check), name="admin-client-ip"),
    path(settings.ADMIN_URL_PATH, admin.site.urls),
    path("api/accounts/", include("accounts.urls")),
    path("api/provider/", include("providers.urls")),
    path("api/catalog/", include("catalog.urls")),
    path("api/", include("messaging.urls")),
    path("api/", include("reviews.urls")),
    path("api/", include("matching.urls")),
    path("api/requests/", ServiceRequestCreateView.as_view(), name="service-request-create"),
    path("api/requests/mine/", ServiceRequestListView.as_view(), name="service-request-list"),
    path("api/requests/<int:request_id>/complete/", ServiceRequestCompleteView.as_view(), name="service-request-complete"),
    path("api/provider-onboarding/", ProviderOnboardingView.as_view(), name="provider-onboarding"),
    path("api/chat/refine/", ChatRefineView.as_view(), name="chat-refine"),
    path("api/twilio/sms/", twilio_sms_webhook, name="twilio-sms-webhook"),
    path("api/notifications/", NotificationListView.as_view(), name="notification-list"),
    path("api/notifications/mark-read/", NotificationMarkReadView.as_view(), name="notification-mark-read"),
    # Marketing website — keep last so admin/ and api/ always take precedence.
    path("", include("website.urls")),
]

# Branded 404 for the website; unmatched /api/ paths still get JSON.
handler404 = "website.views.not_found"
