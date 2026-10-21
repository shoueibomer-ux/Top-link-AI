from django.urls import path

from .views import ClientGoogleSignInView, DeleteAccountView, MeView, TokenRefreshView

# Providers sign in with Google (see the providers app); this app only keeps
# the account's own profile and the token refresh.
urlpatterns = [
    path("google/", ClientGoogleSignInView.as_view(), name="accounts-google-sign-in"),
    path("token/refresh/", TokenRefreshView.as_view(), name="accounts-token-refresh"),
    path("me/", MeView.as_view(), name="accounts-me"),
    path("delete/", DeleteAccountView.as_view(), name="accounts-delete"),
]
