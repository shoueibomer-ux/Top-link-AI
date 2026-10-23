"""Which acquisition channel a new request came from (ServiceRequest.source).

The app sends `source` and `source_ref` with a request when it was opened
from a growth link: an SEO page's "Request this service" button, a seasonal
reminder, or an invite. Anything it sends is checked here against what
actually exists, so a hand-made request can't invent sources. A request with
no source from a client who signed up through an invite counts as that
invite's, but only their first one.
"""

import re

from provider_search.models import ServiceRequest
from website.content.neighbourhoods import NEIGHBOURHOOD_BY_SLUG
from website.content.seo_pages import SEO_PAGES

from .campaigns import CAMPAIGN_BY_SLUG
from .models import InviteCode, InviteSignup

_REF_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,120}$")


def _clean(value) -> str:
    return value.strip() if isinstance(value, str) and _REF_PATTERN.match(value.strip()) else ""


def resolve_link(source, ref) -> tuple[str, str]:
    """A link's src/ref, kept only if they name a real SEO page or campaign ("", "" otherwise). Invites have
    their own links (/invite/<code>/), so they aren't passed this way."""
    source = _clean(source).lower()
    ref = _clean(ref)
    if source == ServiceRequest.SOURCE_SEO:
        return source, ref if ref in NEIGHBOURHOOD_BY_SLUG or ref in SEO_PAGES else ""
    if source == ServiceRequest.SOURCE_SEASONAL:
        return source, ref if ref in CAMPAIGN_BY_SLUG else ""
    return "", ""


def resolve(user, source, ref) -> tuple[str, str]:
    """(source, source_ref) to store on a new request by `user`."""
    linked_source, linked_ref = resolve_link(source, ref)
    if linked_source:
        return linked_source, linked_ref
    signup = InviteSignup.objects.filter(invitee=user).first()
    if _clean(source).lower() == ServiceRequest.SOURCE_INVITE:
        code = _clean(ref).upper()
        if code and InviteCode.objects.filter(code=code).exclude(user=user).exists():
            return ServiceRequest.SOURCE_INVITE, code
        return ServiceRequest.SOURCE_INVITE, signup.code if signup else ""
    if signup and not ServiceRequest.objects.filter(user=user).exists():
        return ServiceRequest.SOURCE_INVITE, signup.code
    return ServiceRequest.SOURCE_DIRECT, ""
