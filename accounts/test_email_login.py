import io
import re
from contextlib import redirect_stdout
from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core import mail
from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone

from providers.models import GoogleIdentity, ProviderProfile

from .deletion import delete_account
from .models import EmailLoginCode, UserProfile, UserRole

User = get_user_model()
TEST_API_KEY = "test-key"
H = {"HTTP_X_API_KEY": TEST_API_KEY}


@override_settings(API_KEY=TEST_API_KEY, EMAIL_HOST_USER="tabmatch@example.com", EMAIL_HOST_PASSWORD="app-password")
class EmailLoginTests(TestCase):
    def setUp(self):
        cache.delete_pattern("rl:*")

    def start(self, email="pat@example.com", role="customer", **extra):
        return self.client.post("/api/accounts/email/start/", {"email": email, "role": role}, content_type="application/json", **H, **extra)

    def verify(self, code, email="pat@example.com", role="customer", **extra):
        return self.client.post(
            "/api/accounts/email/verify/", {"email": email, "role": role, "code": code}, content_type="application/json", **H, **extra
        )

    def last_code(self):
        return re.search(r"\b(\d{6})\b", mail.outbox[-1].subject).group(1)

    def test_status(self):
        self.assertTrue(self.client.get("/api/accounts/email/status/", **H).json()["enabled"])
        with override_settings(EMAIL_HOST_USER="", EMAIL_HOST_PASSWORD=""):
            self.assertFalse(self.client.get("/api/accounts/email/status/", **H).json()["enabled"])

    def test_a_new_email_gets_a_code_and_a_new_client_account(self):
        response = self.start("  Pat@Example.com ")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(mail.outbox[0].to, ["pat@example.com"])
        code = self.last_code()
        self.assertIn(code, mail.outbox[0].body)
        self.assertNotIn(code, str(EmailLoginCode.objects.values_list("code_hash", flat=True)[0]))  # only a hash stored
        body = self.verify(code).json()
        self.assertTrue(body["is_new_account"])
        self.assertTrue(body["access"] and body["refresh"])
        user = User.objects.get(email="pat@example.com")
        self.assertEqual(user.profile.role, UserRole.CUSTOMER)
        self.assertFalse(user.has_usable_password())
        me = self.client.get("/api/accounts/me/", HTTP_AUTHORIZATION=f"Bearer {body['access']}", **H)
        self.assertEqual(me.json()["email"], "pat@example.com")

    def test_an_existing_email_signs_into_the_same_account_even_one_made_with_google(self):
        user = User.objects.create_user(username="pat@example.com", email="Pat@example.com")
        UserProfile.objects.create(user=user, role=UserRole.CUSTOMER, full_name="Pat Client")
        GoogleIdentity.objects.create(user=user, sub="google-123")
        self.start()
        body = self.verify(self.last_code()).json()
        self.assertFalse(body["is_new_account"])
        self.assertEqual(body["full_name"], "Pat Client")
        self.assertEqual(User.objects.count(), 1)

    def test_providers_sign_in_the_same_way_and_get_their_profile(self):
        self.start("ace@example.com", "provider")
        body = self.verify(self.last_code(), "ace@example.com", "provider").json()
        self.assertIsNone(body["profile"])
        user = User.objects.get(email="ace@example.com")
        self.assertEqual(user.profile.role, UserRole.PROVIDER)
        ProviderProfile.objects.create(user=user, business_name="Ace", phone="+17805550101", email="ace@example.com")
        self.start("ace@example.com", "provider")
        self.assertEqual(self.verify(self.last_code(), "ace@example.com", "provider").json()["profile"]["business_name"], "Ace")

    def test_an_email_of_the_other_role_is_refused_only_after_the_code(self):
        self.start("ace@example.com", "provider")
        self.verify(self.last_code(), "ace@example.com", "provider")
        response = self.start("ace@example.com", "customer")
        self.assertEqual(response.status_code, 200)  # asking for a code says nothing about the account
        response = self.verify(self.last_code(), "ace@example.com", "customer")
        self.assertEqual(response.status_code, 409)
        self.assertIn("provider account", response.json()["detail"])

    def test_asking_for_a_code_answers_the_same_with_or_without_an_account(self):
        self.start("ace@example.com", "provider")
        self.verify(self.last_code(), "ace@example.com", "provider")
        known = self.start("ace@example.com", "customer").json()
        unknown = self.start("nobody@example.com", "customer").json()
        self.assertEqual(known, unknown)

    def test_a_code_works_once(self):
        self.start()
        code = self.last_code()
        self.assertEqual(self.verify(code).status_code, 200)
        self.assertEqual(self.verify(code).status_code, 400)

    def test_a_code_expires_after_ten_minutes(self):
        self.start()
        code = self.last_code()
        EmailLoginCode.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        response = self.verify(code)
        self.assertEqual(response.status_code, 400)
        self.assertIn("wrong or has expired", response.json()["detail"])

    def test_ten_minute_lifetime(self):
        self.start()
        row = EmailLoginCode.objects.get()
        self.assertAlmostEqual((row.expires_at - row.created_at).total_seconds(), 600, delta=2)

    def test_five_wrong_tries_lock_the_code(self):
        self.start()
        code = self.last_code()
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(5):
            self.assertEqual(self.verify(wrong).status_code, 400)
        self.assertEqual(self.verify(code).status_code, 400)  # even the right code no longer works
        self.assertFalse(User.objects.exists())

    def test_a_new_code_replaces_the_old_one(self):
        self.start()
        first = self.last_code()
        self.start()
        second = self.last_code()
        if first != second:
            self.assertEqual(self.verify(first).status_code, 400)
        self.assertEqual(self.verify(second).status_code, 200)

    def test_a_code_for_one_role_does_not_sign_in_as_the_other(self):
        self.start(role="customer")
        self.assertEqual(self.verify(self.last_code(), role="provider").status_code, 400)

    def test_sends_are_rate_limited_per_address_and_per_ip(self):
        for _ in range(5):
            self.assertEqual(self.start().status_code, 200)
        self.assertEqual(self.start().status_code, 429)
        self.assertEqual(self.start("other@example.com").status_code, 200)  # another address is fine
        cache.delete_pattern("rl:*")
        for i in range(20):
            self.start(f"p{i}@example.com", REMOTE_ADDR="10.0.0.9")
        self.assertEqual(self.start("p99@example.com", REMOTE_ADDR="10.0.0.9").status_code, 429)
        self.assertEqual(self.start("p99@example.com", REMOTE_ADDR="10.0.0.10").status_code, 200)

    def test_checks_are_rate_limited_per_address(self):
        for _ in range(15):
            self.verify("123456")
        self.assertEqual(self.verify("123456").status_code, 429)

    def test_bad_input(self):
        self.assertEqual(self.start("not-an-email").status_code, 400)
        self.assertEqual(self.start(role="admin").status_code, 400)
        self.assertEqual(self.verify("123456", role="admin").status_code, 400)
        self.assertEqual(self.verify(["123456"]).status_code, 400)
        self.assertEqual(mail.outbox, [])

    def test_disabled_accounts_cannot_sign_in(self):
        user = User.objects.create_user(username="pat@example.com", email="pat@example.com", is_active=False)
        UserProfile.objects.create(user=user, role=UserRole.CUSTOMER)
        self.start()
        self.assertEqual(self.verify(self.last_code()).status_code, 409)

    def test_off_without_email_settings(self):
        with override_settings(EMAIL_HOST_USER="", EMAIL_HOST_PASSWORD=""):
            self.assertEqual(self.start().status_code, 503)
            self.assertEqual(self.verify("123456").status_code, 503)
        self.assertEqual(mail.outbox, [])

    def test_a_mail_server_failure_is_a_clean_503(self):
        with patch("accounts.email_login.send_mail", side_effect=OSError("smtp down")):
            self.assertEqual(self.start().status_code, 503)

    @override_settings(DEBUG=True, EMAIL_HOST_USER="", EMAIL_HOST_PASSWORD="")
    def test_local_development_prints_the_code_instead_of_sending_it(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(self.start().status_code, 200)
        self.assertEqual(mail.outbox, [])
        code = re.search(r"code for pat@example.com: (\d{6})", out.getvalue()).group(1)
        self.assertEqual(self.verify(code).status_code, 200)

    def test_deleting_the_account_removes_its_codes(self):
        self.start()
        self.verify(self.last_code())
        self.start()
        delete_account(User.objects.get(email="pat@example.com"))
        self.assertFalse(EmailLoginCode.objects.exists())
