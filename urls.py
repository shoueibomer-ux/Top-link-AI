from django.urls import path
from .views import ProfileCreateView, MatchView

urlpatterns = [
    path("profiles/", ProfileCreateView.as_view(), name="profile-create"),
    path("match/", MatchView.as_view(), name="match"),
]
