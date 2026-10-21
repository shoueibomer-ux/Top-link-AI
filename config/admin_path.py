"""Where the Django admin is mounted (ADMIN_URL_PATH), checked at startup.

Kept apart from settings.py, with no Django imports, so it can be tested.
"""

import re

from django.core.exceptions import ImproperlyConfigured

_WELL_KNOWN = {"admin", "api", "static"}


def admin_url_path(raw, debug):
    """'manage-x7/' style prefix for the admin. Unset falls back to the
    well-known 'admin/' only in DEBUG; with DEBUG off a non-obvious path is
    required, so production never serves the admin at /admin/."""
    path = (raw or "").strip().strip("/")
    if not path:
        if debug:
            return "admin/"
        raise ImproperlyConfigured("ADMIN_URL_PATH must be set in the environment when DEBUG=False.")
    if not re.fullmatch(r"[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*", path):
        raise ImproperlyConfigured("ADMIN_URL_PATH may only contain letters, digits, '-', '_' and '/'.")
    if not debug and path.lower() in _WELL_KNOWN:
        raise ImproperlyConfigured("ADMIN_URL_PATH must not be a well-known path like 'admin' when DEBUG=False.")
    return path + "/"
