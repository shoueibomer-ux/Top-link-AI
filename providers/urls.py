from django.urls import path

from .views import GoogleSignInView, ProviderLeadsView, ProviderMatchesView, ProviderProfileView

urlpatterns = [
    path("auth/google/", GoogleSignInView.as_view(), name="provider-google-sign-in"),
    path("profile/", ProviderProfileView.as_view(), name="provider-profile"),
    path("leads/", ProviderLeadsView.as_view(), name="provider-leads"),
    path("matches/", ProviderMatchesView.as_view(), name="provider-matches"),
]
