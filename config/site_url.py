"""The website's one public address (SITE_URL, e.g. https://tabmatch.ca).

The same service answers on several hosts: tabmatch.ca, www.tabmatch.ca and
Render's *.onrender.com hostname. Search engines and shared links should only
ever see SITE_URL, so absolute links are built from it, and the other hosts
redirect website pages to it (see CanonicalHostMiddleware).
"""

from django.conf import settings
from django.http import HttpResponsePermanentRedirect


def absolute_url(request, path: str) -> str:
    """`path` (starting with "/") on SITE_URL, or on the request's own host when SITE_URL is unset."""
    if settings.SITE_URL:
        return settings.SITE_URL + path
    return request.build_absolute_uri(path)


class CanonicalHostMiddleware:
    """301 website pages on SITE_REDIRECT_HOSTS (www. and the onrender.com host) to SITE_URL.

    Never redirected:
      - /api/: app builds already installed call the onrender.com host, and an
        HTTP client would drop the POST body and auth headers on a redirect.
      - anything but GET/HEAD: the unsubscribe page takes mail apps' one-click
        POSTs, which a redirect would break.
      - /robots.txt: Render's health check, which must answer 200 on any host.
      - the admin, which isn't a website page.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if self._should_redirect(request):
            return HttpResponsePermanentRedirect(settings.SITE_URL + request.get_full_path())
        return self.get_response(request)

    @staticmethod
    def _should_redirect(request) -> bool:
        if not settings.SITE_REDIRECT_HOSTS or request.method not in ("GET", "HEAD"):
            return False
        path = request.path_info
        if path.startswith("/api/") or path == "/robots.txt":
            return False
        if path.startswith("/" + settings.ADMIN_URL_PATH.rstrip("/")):
            return False
        return request.get_host().lower() in settings.SITE_REDIRECT_HOSTS
