"""The real client address behind Render's proxy, for rate limiting.

django-ratelimit reads REMOTE_ADDR by default, which behind Render is the
proxy's own address, so every user shared one bucket. Settings point
RATELIMIT_IP_META_KEY here instead.

X-Forwarded-For is a list each proxy appends to, so only its right end can be
trusted: Render's proxy does not strip a copy the client sent, it adds the
address it saw. The leftmost entry is whatever the client typed. With
TRUSTED_PROXY_HOPS proxies in front of the app (1 on Render), the client is
the HOPS-th entry from the right; everything left of it is ignored.

With TRUSTED_PROXY_HOPS = 0 (not behind a proxy, e.g. runserver) the header is
ignored entirely, since anyone could set it.
"""

import ipaddress

from django.conf import settings


def _valid_ip(value):
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        return None


def client_ip(request):
    remote_addr = request.META.get("REMOTE_ADDR", "")
    hops = getattr(settings, "TRUSTED_PROXY_HOPS", 0)
    if hops > 0:
        forwarded = [e.strip() for e in request.META.get("HTTP_X_FORWARDED_FOR", "").split(",") if e.strip()]
        if len(forwarded) >= hops:
            ip = _valid_ip(forwarded[-hops])
            if ip:
                return ip
    # No usable header (a request that skipped the proxy, or a malformed
    # value): fall back to the connecting address rather than failing the
    # request. Behind Render that is the shared proxy bucket, never a value
    # the client chose.
    return remote_addr
