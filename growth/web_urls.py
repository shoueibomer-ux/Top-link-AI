from django.urls import path

from . import web_views

app_name = "growth"

urlpatterns = [
    path("open/request/", web_views.open_request, name="open-request"),
    path("invite/<str:code>/", web_views.invite, name="invite"),
    path("reminders/unsubscribe/<str:token>/", web_views.unsubscribe, name="unsubscribe"),
]
