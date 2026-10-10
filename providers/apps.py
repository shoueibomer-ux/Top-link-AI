from django.apps import AppConfig
from django.conf import settings
from django.core import checks


def check_dev_fake_auth(app_configs=None, **kwargs):
    """The fake Google sign-in must never be switched on outside DEBUG: it
    would let anyone become any provider by typing an email."""
    if settings.GOOGLE_DEV_FAKE_AUTH and not settings.DEBUG:
        return [
            checks.Error(
                "GOOGLE_DEV_FAKE_AUTH is on while DEBUG is off.",
                hint="Remove GOOGLE_DEV_FAKE_AUTH from this environment; it is for local development only.",
                id="providers.E001",
            )
        ]
    return []


class ProvidersConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "providers"

    def ready(self):
        checks.register(check_dev_fake_auth)
