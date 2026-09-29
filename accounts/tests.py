import os
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase, override_settings
from rest_framework_simplejwt.tokens import RefreshToken

from .models import UserProfile, UserRole

User = get_user_model()
TEST_API_KEY = "test-key"
_PASSWORD = "S3cure-Passphrase-2026"


@override_settings(
    API_KEY=TEST_API_KEY,
    # Django's real password hasher is deliberately slow (authenticate()
    # hashes the submitted password even on a wrong guess, to avoid a
    # timing leak) — slow enough that 5-6 sequential login attempts can
    # cross django-ratelimit's window boundary mid-test (its windows are
    # time-jittered per key) and silently reset the counter, making these
    # tests flaky through no fault of the rate-limiting logic itself. A
    # fast hasher is the standard fix for exactly this in Django tests.
    PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"],
)
class AuthRateLimitTests(TestCase):
    """Security audit finding H2: /register/, /login/, and /token/refresh/
    previously had no rate limiting at all — unlimited password-guessing
    against a real account, and unlimited automated account creation."""

    def setUp(self):
        self.headers = {"HTTP_X_API_KEY": TEST_API_KEY}
        # django-ratelimit's counters live in the real Redis-backed `default`
        # cache (TestCase only wraps the DB in a transaction, not the
        # cache), so a prior test run's counters would otherwise leak in
        # here. Only clear django-ratelimit's own keys ("rl:" prefix, the
        # library's default) — never the whole cache, which could also hold
        # unrelated data (e.g. a dev's cached Google Places results) if this
        # ever runs against a shared, non-test Redis instance.
        cache.delete_pattern("rl:*")

    def tearDown(self):
        cache.delete_pattern("rl:*")

    def _make_user(self, email, role=UserRole.CUSTOMER):
        user = User.objects.create_user(username=email, email=email, password=_PASSWORD)
        UserProfile.objects.create(user=user, role=role, full_name="Test User")
        return user

    def _register(self, email):
        return self.client.post(
            "/api/accounts/register/",
            {"email": email, "password": _PASSWORD, "role": UserRole.CUSTOMER},
            content_type="application/json",
            **self.headers,
        )

    def _login(self, email, password=_PASSWORD):
        return self.client.post(
            "/api/accounts/login/",
            {"email": email, "password": password},
            content_type="application/json",
            **self.headers,
        )

    def _refresh(self, token):
        return self.client.post(
            "/api/accounts/token/refresh/",
            {"refresh": token},
            content_type="application/json",
            **self.headers,
        )

    # ---- login: capped per targeted account ----

    def test_login_is_rate_limited_per_account_after_five_attempts(self):
        self._make_user("victim@example.com")

        for _ in range(5):
            response = self._login("victim@example.com", password="wrong-guess")
            self.assertEqual(response.status_code, 401)  # ordinary invalid-credentials response

        sixth = self._login("victim@example.com", password="wrong-guess")
        self.assertEqual(sixth.status_code, 429)

    def test_login_rate_limit_is_scoped_per_account_not_global(self):
        self._make_user("target@example.com")
        self._make_user("bystander@example.com")

        for _ in range(5):
            self._login("target@example.com", password="wrong-guess")
        self.assertEqual(self._login("target@example.com", password="wrong-guess").status_code, 429)

        # A different account, hit from the same source, is unaffected —
        # this is the whole point of keying on the submitted email rather
        # than only the IP.
        response = self._login("bystander@example.com", password="wrong-guess")
        self.assertEqual(response.status_code, 401)

    def test_a_correct_login_still_succeeds_under_the_cap(self):
        self._make_user("real-user@example.com")
        response = self._login("real-user@example.com")
        self.assertEqual(response.status_code, 200)
        self.assertIn("access", response.json())
        self.assertIn("refresh", response.json())

    # ---- register: capped per source ----

    def test_register_is_rate_limited_per_source_after_five_attempts(self):
        for i in range(5):
            response = self._register(f"user{i}@example.com")
            self.assertEqual(response.status_code, 201)

        sixth = self._register("user5@example.com")
        self.assertEqual(sixth.status_code, 429)
        # And the 6th attempt's email must not have been created either —
        # a 429 has to mean "rejected", not "rejected but still applied".
        self.assertFalse(User.objects.filter(email="user5@example.com").exists())

    # ---- token refresh: capped per source ----

    def test_token_refresh_is_rate_limited_after_thirty_attempts(self):
        user = self._make_user("refresher@example.com")
        refresh_token = str(RefreshToken.for_user(user))

        for _ in range(30):
            response = self._refresh(refresh_token)
            self.assertEqual(response.status_code, 200)

        thirty_first = self._refresh(refresh_token)
        self.assertEqual(thirty_first.status_code, 429)


@override_settings(API_KEY=TEST_API_KEY, PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"])
class AccountEditTests(TestCase):
    """PATCH /api/accounts/me/ — the Settings screen's Account row."""

    def setUp(self):
        self.headers = {"HTTP_X_API_KEY": TEST_API_KEY}
        cache.delete_pattern("rl:*")
        self.user = self._make_user("owner@example.com", full_name="Olive Owner")

    def tearDown(self):
        cache.delete_pattern("rl:*")

    def _make_user(self, email, role=UserRole.CUSTOMER, full_name="Test User"):
        user = User.objects.create_user(username=email, email=email, password=_PASSWORD)
        UserProfile.objects.create(user=user, role=role, full_name=full_name)
        return user

    def _auth(self, user):
        return {**self.headers, "HTTP_AUTHORIZATION": f"Bearer {RefreshToken.for_user(user).access_token}"}

    def _patch(self, body, user=None):
        return self.client.patch(
            "/api/accounts/me/", body, content_type="application/json", **self._auth(user or self.user)
        )

    def test_a_name_change_is_saved_and_returned(self):
        response = self._patch({"full_name": "  Olive Q. Owner "})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["full_name"], "Olive Q. Owner")  # trimmed
        self.user.profile.refresh_from_db()
        self.assertEqual(self.user.profile.full_name, "Olive Q. Owner")

    def test_an_email_change_updates_the_username_too_so_login_keeps_working(self):
        response = self._patch({"email": "new-address@example.com"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["email"], "new-address@example.com")
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "new-address@example.com")
        self.assertEqual(self.user.username, "new-address@example.com")

        login = lambda email: self.client.post(  # noqa: E731
            "/api/accounts/login/", {"email": email, "password": _PASSWORD},
            content_type="application/json", **self.headers,
        )
        self.assertEqual(login("new-address@example.com").status_code, 200)
        old = login("owner@example.com")  # the old address no longer signs in
        self.assertEqual(old.status_code, 400)  # unknown email -> "Invalid email or password."
        self.assertNotIn("access", old.json())

    def test_changing_only_the_name_leaves_the_email_alone(self):
        self._patch({"full_name": "Someone Else"})
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "owner@example.com")

    def test_an_email_already_used_by_another_account_is_rejected_case_insensitively(self):
        self._make_user("taken@example.com")
        response = self._patch({"email": "Taken@Example.com"})

        self.assertEqual(response.status_code, 400)
        self.assertIn("already exists", str(response.json()["email"]))
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "owner@example.com")

    def test_re_submitting_your_own_email_is_not_a_conflict(self):
        self.assertEqual(self._patch({"email": "owner@example.com", "full_name": "Olive"}).status_code, 200)

    def test_an_invalid_email_is_rejected(self):
        self.assertEqual(self._patch({"email": "not-an-email"}).status_code, 400)

    def test_a_blank_name_is_allowed_a_blank_email_is_not(self):
        self.assertEqual(self._patch({"full_name": ""}).status_code, 200)
        self.assertEqual(self._patch({"email": ""}).status_code, 400)

    def test_role_cannot_be_changed_so_nobody_can_promote_themselves(self):
        response = self._patch({"role": UserRole.ADMIN, "full_name": "Olive"})

        self.assertEqual(response.status_code, 200)
        self.user.profile.refresh_from_db()
        self.assertEqual(self.user.profile.role, UserRole.CUSTOMER)
        self.assertEqual(response.json()["role"], UserRole.CUSTOMER)

    def test_you_can_only_edit_your_own_account(self):
        other = self._make_user("other@example.com", full_name="Other Person")
        self._patch({"full_name": "Hijacked"})  # authenticated as self.user; no way to name another account

        other.profile.refresh_from_db()
        self.assertEqual(other.profile.full_name, "Other Person")

    def test_providers_can_edit_their_account_too(self):
        provider = self._make_user("pro@example.com", role=UserRole.PROVIDER, full_name="Pat")
        response = self._patch({"full_name": "Pat Provider"}, user=provider)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["full_name"], "Pat Provider")
        self.assertEqual(response.json()["role"], UserRole.PROVIDER)

    def test_it_requires_authentication_and_the_api_key(self):
        anonymous = self.client.patch(
            "/api/accounts/me/", {"full_name": "x"}, content_type="application/json", **self.headers
        )
        self.assertEqual(anonymous.status_code, 401)
        no_key = self.client.patch(
            "/api/accounts/me/", {"full_name": "x"}, content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(self.user).access_token}",
        )
        # Authenticated, but HasApiKey denies it: 403 (not 401, which is for
        # requests that aren't authenticated at all).
        self.assertEqual(no_key.status_code, 403)


class CreateSuperuserFromEnvCommandTests(TestCase):
    """accounts.management.commands.create_superuser_from_env — bootstraps a
    Django admin login on a fresh deploy (see build.sh)."""

    _ENV = {
        "DJANGO_SUPERUSER_USERNAME": "opsadmin",
        "DJANGO_SUPERUSER_EMAIL": "opsadmin@example.com",
        "DJANGO_SUPERUSER_PASSWORD": _PASSWORD,
    }

    def _run(self):
        call_command("create_superuser_from_env")

    def test_creates_the_superuser_when_all_three_vars_are_set(self):
        with patch.dict(os.environ, self._ENV):
            self._run()

        user = User.objects.get(username="opsadmin")
        self.assertTrue(user.is_superuser)
        self.assertTrue(user.is_staff)
        self.assertEqual(user.email, "opsadmin@example.com")
        self.assertTrue(user.check_password(_PASSWORD))

    def test_is_a_noop_when_any_one_var_is_missing(self):
        for missing in self._ENV:
            with self.subTest(missing=missing):
                env = {k: v for k, v in self._ENV.items() if k != missing}
                # Clearing, not just omitting: the real environment (or an
                # earlier subTest's patch) must not leak a value in.
                with patch.dict(os.environ, env, clear=True):
                    self._run()
                self.assertFalse(User.objects.filter(username="opsadmin").exists())

    def test_is_a_noop_when_none_are_set(self):
        with patch.dict(os.environ, {}, clear=True):
            self._run()
        self.assertEqual(User.objects.count(), 0)

    def test_running_it_twice_only_creates_the_account_once(self):
        with patch.dict(os.environ, self._ENV):
            self._run()
            self._run()  # e.g. build.sh running again on the next deploy

        self.assertEqual(User.objects.filter(username="opsadmin").count(), 1)

    def test_an_existing_account_with_that_username_is_left_alone(self):
        existing = User.objects.create_user(username="opsadmin", email="original@example.com", password="whatever")
        self.assertFalse(existing.is_superuser)

        with patch.dict(os.environ, self._ENV):
            self._run()

        existing.refresh_from_db()
        self.assertFalse(existing.is_superuser)  # not promoted
        self.assertEqual(existing.email, "original@example.com")  # not overwritten
        self.assertEqual(User.objects.filter(username="opsadmin").count(), 1)  # not duplicated
