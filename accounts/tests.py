from django.contrib.auth import get_user_model
from django.core.cache import cache
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
