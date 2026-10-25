import json
import os
import subprocess
import sys
from pathlib import Path

from django.test import SimpleTestCase

from config.env import strip_environ

ROOT = Path(__file__).resolve().parent.parent


class StripEnvironTests(SimpleTestCase):
    def test_values_lose_surrounding_whitespace_and_newlines(self):
        env = {"EMAIL_HOST": "smtp-relay.brevo.com\n\n", "API_KEY": "  key\r\n", "EMPTY": " \n", "CLEAN": "as is"}
        self.assertEqual(sorted(strip_environ(env)), ["API_KEY", "EMAIL_HOST", "EMPTY"])
        self.assertEqual(env, {"EMAIL_HOST": "smtp-relay.brevo.com", "API_KEY": "key", "EMPTY": "", "CLEAN": "as is"})

    def test_inner_whitespace_is_kept(self):
        env = {"DEFAULT_FROM_EMAIL": " Tabmatch <connect@tabmatch.ca>\n"}
        strip_environ(env)
        self.assertEqual(env["DEFAULT_FROM_EMAIL"], "Tabmatch <connect@tabmatch.ca>")

    def test_settings_see_clean_values_as_pasted_into_render(self):
        """A real settings load in a fresh process, with values the way Render's form can save them."""
        pasted = {
            "DJANGO_DEBUG": "False\n",
            "DJANGO_SECRET_KEY": "x" * 60 + "\n",
            "API_KEY": "prod-like-key\n",
            "ADMIN_URL_PATH": "manage-prod-like\n",
            "DATABASE_URL": "postgres://nobody:nothing@localhost:5432/never_connected\n",
            "EMAIL_HOST": "smtp-relay.brevo.com\n\n",
            "EMAIL_PORT": " 587\n",
            "EMAIL_HOST_USER": "12345@smtp-brevo.com\n",
            "DEFAULT_FROM_EMAIL": "Tabmatch <connect@tabmatch.ca>\n\n",
            "DJANGO_ALLOWED_HOSTS": "tabmatch.ca, www.tabmatch.ca\n",
            "SITE_URL": "https://tabmatch.ca\n",
            "WEBSITE_CONTACT_EMAIL": "connect@tabmatch.ca\n",
        }
        probe = (
            "import json, os, django; os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings'); django.setup();"
            "from django.conf import settings; from website import config;"
            "print(json.dumps([settings.DEBUG, settings.EMAIL_HOST, settings.EMAIL_PORT, settings.EMAIL_HOST_USER,"
            " settings.DEFAULT_FROM_EMAIL, settings.ADMIN_URL_PATH, settings.SITE_URL, settings.ALLOWED_HOSTS[:2],"
            " config.CONTACT_EMAIL, os.environ['DATABASE_URL']]))"
        )
        result = subprocess.run(
            [sys.executable, "-c", probe], cwd=ROOT, capture_output=True, text=True, timeout=120,
            env={**{k: v for k, v in os.environ.items() if k not in pasted}, **pasted},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [
            False, "smtp-relay.brevo.com", 587, "12345@smtp-brevo.com", "Tabmatch <connect@tabmatch.ca>",
            "manage-prod-like/", "https://tabmatch.ca", ["tabmatch.ca", "www.tabmatch.ca"], "connect@tabmatch.ca",
            "postgres://nobody:nothing@localhost:5432/never_connected",
        ])
