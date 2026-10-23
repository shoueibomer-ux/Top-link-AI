from django.urls import path

from .views import (
    ClientGoogleSignInView,
    DeleteAccountView,
    EmailLoginStartView,
    EmailLoginStatusView,
    EmailLoginVerifyView,
    MeView,
    TokenRefreshView,
)

# Providers sign in with Google (see the providers app) or with an emailed
# code (here, for both roles); this app also keeps the account's own profile
# and the token refresh.
urlpatterns = [
    path("google/", ClientGoogleSignInView.as_view(), name="accounts-google-sign-in"),
    path("email/status/", EmailLoginStatusView.as_view(), name="accounts-email-status"),
    path("email/start/", EmailLoginStartView.as_view(), name="accounts-email-start"),
    path("email/verify/", EmailLoginVerifyView.as_view(), name="accounts-email-verify"),
    path("token/refresh/", TokenRefreshView.as_view(), name="accounts-token-refresh"),
    path("me/", MeView.as_view(), name="accounts-me"),
    path("delete/", DeleteAccountView.as_view(), name="accounts-delete"),
]
