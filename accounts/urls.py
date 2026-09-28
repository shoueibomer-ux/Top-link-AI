from django.urls import path

from .views import LoginView, MeView, ProviderProfileView, RegisterView, TokenRefreshView

urlpatterns = [
    path("register/", RegisterView.as_view(), name="accounts-register"),
    path("login/", LoginView.as_view(), name="accounts-login"),
    path("token/refresh/", TokenRefreshView.as_view(), name="accounts-token-refresh"),
    path("me/", MeView.as_view(), name="accounts-me"),
    path("provider-profile/", ProviderProfileView.as_view(), name="accounts-provider-profile"),
]
