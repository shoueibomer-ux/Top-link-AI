from django.urls import path

from .views import InviteClaimView, InviteView, ReminderPreferenceView

urlpatterns = [
    path("invite/", InviteView.as_view(), name="growth-invite"),
    path("invite/claim/", InviteClaimView.as_view(), name="growth-invite-claim"),
    path("reminders/", ReminderPreferenceView.as_view(), name="growth-reminders"),
]
