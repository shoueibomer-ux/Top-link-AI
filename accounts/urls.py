from django.urls import path

from .views import MeView, TokenRefreshView

# Providers sign in with Google (see the providers app); this app only keeps
# the account's own profile and the token refresh.
urlpatterns = [
    path("token/refresh/", TokenRefreshView.as_view(), name="accounts-token-refresh"),
    path("me/", MeView.as_view(), name="accounts-me"),
]
