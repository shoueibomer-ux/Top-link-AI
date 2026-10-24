"""Host lists derived from the environment, for config/settings.py (no Django imports, so settings can use them)."""

from urllib.parse import urlsplit


def csrf_trusted_origins(allowed_hosts):
    """https:// origins for ALLOWED_HOSTS: ".example.com" becomes "https://*.example.com", "*" is skipped."""
    return [f"https://*{h}" if h.startswith(".") else f"https://{h}" for h in allowed_hosts if h != "*"]


def site_redirect_hosts(site_url, render_hostname):
    """Hosts whose website pages 301 to SITE_URL: "www." plus SITE_URL's host, and the *.onrender.com hostname.

    Empty unless SITE_URL is https://, so local development (http://localhost:8000) never redirects.
    """
    if not site_url.startswith("https://"):
        return set()
    site_host = urlsplit(site_url).netloc.lower()
    return {h.lower() for h in (f"www.{site_host}", render_hostname) if h and h.lower() != site_host}
