from django.urls import path

from .views import (
    GoogleSignInView,
    ProviderLeadReplyView,
    ProviderLeadsView,
    ProviderMatchesView,
    ProviderProfileView,
)

urlpatterns = [
    path("auth/google/", GoogleSignInView.as_view(), name="provider-google-sign-in"),
    path("profile/", ProviderProfileView.as_view(), name="provider-profile"),
    path("leads/", ProviderLeadsView.as_view(), name="provider-leads"),
    path("leads/<int:offer_id>/accept/", ProviderLeadReplyView.as_view(verb="accept"), name="provider-lead-accept"),
    path("leads/<int:offer_id>/decline/", ProviderLeadReplyView.as_view(verb="decline"), name="provider-lead-decline"),
    path("matches/", ProviderMatchesView.as_view(), name="provider-matches"),
]
