"""The website pages behind growth links: they hand the visitor to the app
(tabmatch://open/...) or, without the app, to the get-the-app page. All
noindex, and disallowed in robots.txt."""

from django.contrib.auth import get_user_model
from django.http import Http404
from django.shortcuts import render
from django.urls import reverse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from catalog.models import Service
from providers.models import ProviderProfile
from website import config

from . import attribution, links
from .models import InviteCode, ReminderPreference


def _meta(title: str, description: str) -> dict:
    return {"meta": {"title": title, "description": description, "robots": "noindex,nofollow"}}


def _get_app_url() -> str:
    return config.APP_URL or reverse("website:get-app")


def open_request(request):
    """/open/request/?service=<slug>&src=<source>&ref=<ref> — "Request this service"."""
    service = Service.objects.filter(
        slug=request.GET.get("service", ""), is_active=True, is_launched=True, category__is_active=True
    ).first()
    if service is None:
        raise Http404
    source, ref = attribution.resolve_link(request.GET.get("src"), request.GET.get("ref"))
    return render(
        request,
        "growth/open_request.html",
        {
            **_meta(f"Request {service.name} | Tabmatch", f"Request {service.name} in the Tabmatch app."),
            "service": service,
            "app_link": links.app_request_link(service.slug, source, ref),
            "get_app_url": _get_app_url(),
        },
    )


def invite(request, code):
    """/invite/<code>/[?provider=<id>] — a client's invite link."""
    invite = InviteCode.objects.filter(code=code.upper(), user__is_active=True).first()
    if invite is None:
        raise Http404
    provider_id = request.GET.get("provider", "")
    provider = (
        ProviderProfile.objects.approved().filter(pk=int(provider_id)).first() if provider_id.isdigit() else None
    )
    return render(
        request,
        "growth/invite.html",
        {
            **_meta("You're invited to Tabmatch", "Find trusted local service providers in Edmonton with Tabmatch."),
            "code": invite.code,
            "provider": provider,
            "app_link": links.app_invite_link(invite.code, provider.pk if provider else None),
            "get_app_url": _get_app_url(),
        },
    )


@csrf_exempt  # the signed token is the proof; mail apps' one-click unsubscribe POSTs here without a CSRF token
@require_http_methods(["GET", "POST"])
def unsubscribe(request, token):
    """GET shows a confirm button (link scanners in mail apps open links, so a GET must never unsubscribe);
    POST turns seasonal reminders off, from that button or a mail app's one-click unsubscribe."""
    user_id = links.user_id_from_unsubscribe_token(token)
    user = get_user_model().objects.filter(pk=user_id).first() if user_id else None
    if user is None:
        raise Http404
    done = False
    if request.method == "POST":
        ReminderPreference.set_for(user, False, ReminderPreference.VIA_EMAIL)
        done = True
    return render(
        request,
        "growth/unsubscribe.html",
        {**_meta("Seasonal reminders | Tabmatch", "Turn off Tabmatch seasonal reminders."), "done": done},
    )
