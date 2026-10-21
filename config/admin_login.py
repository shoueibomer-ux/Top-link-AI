"""Rate-limited Django admin login.

Mounted at <admin path>/login/ ahead of admin.site.urls (see config/urls.py),
so it answers the login form in place of the admin's own view and then hands
off to it. Two limits, both counting every POST: per client IP (see
config.client_ip), and per username tried, so guessing one account's password
from many addresses is capped too.
"""

from django.contrib import admin
from django.http import HttpResponse
from django_ratelimit.decorators import ratelimit

ADMIN_LOGIN_IP_RATE = "5/m"
ADMIN_LOGIN_USERNAME_RATE = "10/h"


def _username_key(group, request):
    return request.POST.get("username", "").strip().lower()


@ratelimit(key="ip", rate=ADMIN_LOGIN_IP_RATE, method="POST", block=False)
@ratelimit(key=_username_key, rate=ADMIN_LOGIN_USERNAME_RATE, method="POST", block=False)
def admin_login(request, extra_context=None):
    if getattr(request, "limited", False):
        return HttpResponse("Too many login attempts. Try again later.", status=429, content_type="text/plain")
    return admin.site.login(request, extra_context)
