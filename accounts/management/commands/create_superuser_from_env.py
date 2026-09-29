import os

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    """Bootstraps a Django admin login on a fresh deploy, where there's no
    interactive shell to run `createsuperuser` in (see build.sh).

    Reads DJANGO_SUPERUSER_USERNAME / DJANGO_SUPERUSER_EMAIL /
    DJANGO_SUPERUSER_PASSWORD — the same three env var names Django's own
    `createsuperuser --noinput` reads — and creates that superuser if all
    three are set and no user with that username exists yet. A no-op
    otherwise (env vars not set, or the username is already taken), so it's
    safe to run on every deploy rather than only the first one.

    Deliberately narrower than `createsuperuser --noinput`: that command
    errors out if the username is already taken, which would fail the build
    on every deploy after the first. This checks first and skips instead.
    Only ever creates a new user — an existing account with that username
    (superuser or not) is left exactly as it is.
    """

    help = "Creates a superuser from DJANGO_SUPERUSER_* env vars if set and the user doesn't already exist."

    def handle(self, *args, **options):
        username = os.environ.get("DJANGO_SUPERUSER_USERNAME")
        email = os.environ.get("DJANGO_SUPERUSER_EMAIL")
        password = os.environ.get("DJANGO_SUPERUSER_PASSWORD")

        if not (username and email and password):
            self.stdout.write("DJANGO_SUPERUSER_USERNAME/_EMAIL/_PASSWORD not all set — skipping.")
            return

        User = get_user_model()
        if User.objects.filter(username=username).exists():
            self.stdout.write(f"A user named {username!r} already exists — skipping.")
            return

        User.objects.create_superuser(username=username, email=email, password=password)
        self.stdout.write(self.style.SUCCESS(f"Created superuser {username!r}."))
