import os
from pathlib import Path

import dj_database_url
from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent

load_dotenv(BASE_DIR / ".env")

DEBUG = os.environ.get("DJANGO_DEBUG", "False") == "True"


def _env(name, dev_default=None):
    """Read a required setting from the environment.

    Falls back to `dev_default` only when DEBUG is on, so local development
    keeps working without a fully-populated .env, while a production
    deployment (DEBUG=False) fails fast at startup instead of silently
    running with a known placeholder secret.
    """
    value = os.environ.get(name)
    if value:
        return value
    if DEBUG:
        return dev_default
    raise ImproperlyConfigured(f"{name} must be set in the environment when DEBUG=False.")


SECRET_KEY = _env("DJANGO_SECRET_KEY", "dev-only-secret-key-do-not-use-in-production")

# Shared secret required on every API request (see matching.permissions.HasApiKey).
# The app has no user accounts, so this isn't per-user auth — it's a gate that
# keeps the open internet off the Claude-backed endpoints.
# Stripped because the app strips the key it sends (lib/api/api_config.dart): a
# trailing space or newline pasted into the host's env var would otherwise make
# every request fail with a key that looks identical.
API_KEY = _env("API_KEY", "dev-local-shared-key").strip()

def _env_flag(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


# --- Lead validation tooling (the leads app) ------------------------------
# SMS_ENABLED is off by default: with it off, "Send to providers" only
# creates the offers and shows ready-to-copy messages to send by hand, and
# nothing here talks to Twilio. Twilio credentials come only from the
# environment, never from the repo, and are not required to start the app.
SMS_ENABLED = _env_flag("SMS_ENABLED", False)
TWILIO_ACCOUNT_SID = os.environ.get("TWILIO_ACCOUNT_SID", "").strip()
TWILIO_AUTH_TOKEN = os.environ.get("TWILIO_AUTH_TOKEN", "").strip()
TWILIO_FROM_NUMBER = os.environ.get("TWILIO_FROM_NUMBER", "").strip()
# Only needed if the public URL Twilio calls differs from what Django sees
# behind the proxy (the signature is computed over that exact URL).
TWILIO_WEBHOOK_URL = os.environ.get("TWILIO_WEBHOOK_URL", "").strip()

# Provider sign-in with Google (the providers app). The Flutter app sends a
# Google ID token; the server only accepts one issued for one of these OAuth
# client IDs (comma-separated; use the Web client ID the app passes as its
# serverClientId). Unset means Google sign-in answers 503.
GOOGLE_OAUTH_CLIENT_IDS = [c.strip() for c in os.environ.get("GOOGLE_OAUTH_CLIENT_IDS", "").split(",") if c.strip()]
# Local development only: accept "dev-fake:<email>" instead of a real Google
# token so the sign-in flow can be tried without a Google Cloud project. The
# app refuses to start with this on and DEBUG off (providers.E001).
GOOGLE_DEV_FAKE_AUTH = _env_flag("GOOGLE_DEV_FAKE_AUTH", False)

# Email (Gmail SMTP with an app password for now). Without EMAIL_HOST_USER,
# mail goes to the console instead of failing.
EMAIL_HOST = os.environ.get("EMAIL_HOST", "smtp.gmail.com")
EMAIL_PORT = int(os.environ.get("EMAIL_PORT", "587"))
EMAIL_USE_TLS = _env_flag("EMAIL_USE_TLS", True)
EMAIL_HOST_USER = os.environ.get("EMAIL_HOST_USER", "").strip()
EMAIL_HOST_PASSWORD = os.environ.get("EMAIL_HOST_PASSWORD", "").strip()
EMAIL_BACKEND = (
    "django.core.mail.backends.smtp.EmailBackend"
    if EMAIL_HOST_USER
    else "django.core.mail.backends.console.EmailBackend"
)
DEFAULT_FROM_EMAIL = os.environ.get("DEFAULT_FROM_EMAIL", "").strip() or EMAIL_HOST_USER or "noreply@localhost"
# Where the 2-hour "no YES" alert and the daily summary are sent.
ADMIN_ALERT_EMAIL = os.environ.get("ADMIN_ALERT_EMAIL", "").strip()

ALLOWED_HOSTS = [h.strip() for h in os.environ.get("DJANGO_ALLOWED_HOSTS", "").split(",") if h.strip()]

# Render sets this for every service automatically (its *.onrender.com
# hostname) — added on top of DJANGO_ALLOWED_HOSTS (for a custom domain, once
# there is one) rather than replacing it, so nothing manual is needed just to
# reach the default Render URL.
_render_hostname = os.environ.get("RENDER_EXTERNAL_HOSTNAME")
if _render_hostname and _render_hostname not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append(_render_hostname)

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "corsheaders",
    "matching",
    "provider_search",
    "notifications",
    "accounts",
    "catalog",
    "leads",
    "providers",
    "website",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    # Serves collected static files directly from the Django process — no
    # separate static-file host needed on Render. Must stay immediately after
    # SecurityMiddleware and above everything else (whitenoise's own
    # requirement).
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

# DATABASE_URL (set automatically on Render — see render.yaml's `fromDatabase`)
# takes priority when present; local development keeps using the separate
# DB_* vars below (or their defaults) so nothing changes for `runserver`.
_database_url = os.environ.get("DATABASE_URL")
if _database_url:
    DATABASES = {
        "default": dj_database_url.parse(
            _database_url,
            conn_max_age=600,
            # Render's internal connection is plaintext-capable but always
            # TLS-optional; its external one requires TLS. Requiring it
            # outside DEBUG covers both without needing to know which one
            # this is — "require" doesn't validate the certificate, so
            # Render's self-signed internal cert isn't a problem.
            ssl_require=not DEBUG,
        )
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": _env("DB_NAME", "toplinkai"),
            "USER": _env("DB_USER", "postgres"),
            "PASSWORD": _env("DB_PASSWORD", "postgres"),
            "HOST": _env("DB_HOST", "localhost"),
            "PORT": _env("DB_PORT", "5432"),
        }
    }

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"

# Where `collectstatic` writes to (see build.sh) and whitenoise serves from.
STATIC_ROOT = BASE_DIR / "staticfiles"

# Nothing in this project uses FileField/ImageField, so "default" here is
# never exercised — set explicitly anyway, since defining STORAGES at all
# replaces Django's built-in default for *both* keys, not just the one
# being overridden.
STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        # Content-hashed filenames + gzip/brotli pre-compression in
        # production, so static assets can be served with a far-future cache
        # header safely. Plain (unhashed) filenames in DEBUG instead — dev
        # doesn't run `collectstatic` on every change, and website.linkcheck's
        # tests resolve {% static %} URLs against the source tree via
        # staticfiles finders, which only know unhashed names.
        "BACKEND": (
            "django.contrib.staticfiles.storage.StaticFilesStorage"
            if DEBUG
            else "whitenoise.storage.CompressedManifestStaticFilesStorage"
        ),
    },
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Redis-backed cache — provider_search relies on this surviving process
# restarts (Google Places results are cached for 35 days; Django's default
# LocMemCache would lose that on every deploy/restart). REDIS_URL is set
# automatically on Render (see render.yaml's `fromService`); falls back to a
# local Redis instance for development.
_redis_url = os.environ.get("REDIS_URL", "redis://127.0.0.1:6379/1")
_redis_options = {"CLIENT_CLASS": "django_redis.client.DefaultClient"}
if _redis_url.startswith("rediss://"):
    # Only reachable with an external (TLS) Redis URL — Render's own internal
    # connection string is plain redis://, so this doesn't apply to the
    # render.yaml setup below, only if that's ever swapped for an external
    # one. "require" without validating the certificate, same reasoning as
    # the database's ssl_require above.
    _redis_options["CONNECTION_POOL_KWARGS"] = {"ssl_cert_reqs": None}
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": _redis_url,
        "OPTIONS": _redis_options,
    }
}

REST_FRAMEWORK = {
    # Fail-safe default: any view (including ones added later) requires the
    # shared API key unless it explicitly opts out. This is unchanged by
    # adding JWT below — auth and permission are separate DRF concerns, so
    # every existing (anonymous, device_id/place_id-keyed) endpoint keeps
    # requiring only the API key, exactly as before.
    "DEFAULT_PERMISSION_CLASSES": ["matching.permissions.HasApiKey"],
    # Populates request.user from a Bearer token when one is present, for
    # the new accounts app's authenticated views (see accounts.views).
    # Session/Basic auth (DRF's own defaults) were never actually relied on
    # by anything in this API, so replacing them here is not a regression.
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ],
}

from datetime import timedelta  # noqa: E402

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=30),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=14),
    "ROTATE_REFRESH_TOKENS": True,
    "AUTH_HEADER_TYPES": ("Bearer",),
    # Signs tokens with the same SECRET_KEY as everything else Django signs
    # (sessions, password reset tokens) — no separate secret to manage, and
    # never hard-coded (SECRET_KEY itself comes from the environment, see
    # `_env()` above).
    "SIGNING_KEY": SECRET_KEY,
}

# CORS is a browser-only mechanism — it does not restrict the native mobile
# app (Android/iOS HTTP clients ignore it entirely). It matters for two
# things: local development against the Flutter *web* build, and stopping
# an arbitrary website from making browser-driven requests to this API on a
# victim's behalf. Allow everything only in dev; require an explicit,
# comma-separated allowlist in production.
CORS_ALLOW_ALL_ORIGINS = DEBUG
if not DEBUG:
    CORS_ALLOWED_ORIGINS = [
        o.strip() for o in os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",") if o.strip()
    ]

# django-cors-headers' default allow-list doesn't include our custom auth
# header, so a browser client's preflight would otherwise fail and the
# actual request would never be sent.
from corsheaders.defaults import default_headers  # noqa: E402

CORS_ALLOW_HEADERS = [*default_headers, "x-api-key"]

# --- Transport security (production only — DEBUG=True means a local HTTP
# dev server, where redirecting to HTTPS or marking cookies Secure would
# just break `runserver`). Security audit finding H1. ---
SECURE_SSL_REDIRECT = not DEBUG
SESSION_COOKIE_SECURE = not DEBUG
CSRF_COOKIE_SECURE = not DEBUG
# 1 year, the standard "submit to hstspreload.org" duration — 0 in DEBUG so
# a browser never caches an HSTS policy for localhost.
SECURE_HSTS_SECONDS = 0 if DEBUG else 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = not DEBUG
SECURE_HSTS_PRELOAD = not DEBUG

# SECURE_SSL_REDIRECT/HSTS both rely on request.is_secure(), which is wrong
# behind a reverse proxy that terminates TLS and forwards plain HTTP
# internally — the request would redirect-loop forever. Trusting
# X-Forwarded-Proto is only safe when a real proxy sets it (and strips any
# client-supplied copy) — never enable this without confirming the actual
# deployment topology, since trusting a client-spoofable header otherwise
# defeats SECURE_SSL_REDIRECT entirely.
if os.environ.get("DJANGO_BEHIND_PROXY") == "True":
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
