import os
from pathlib import Path

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
API_KEY = _env("API_KEY", "dev-local-shared-key")

ALLOWED_HOSTS = [h.strip() for h in os.environ.get("DJANGO_ALLOWED_HOSTS", "").split(",") if h.strip()]

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
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
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

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    # Fail-safe default: any view (including ones added later) requires the
    # shared API key unless it explicitly opts out.
    "DEFAULT_PERMISSION_CLASSES": ["matching.permissions.HasApiKey"],
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
