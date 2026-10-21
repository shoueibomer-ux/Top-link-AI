import importlib

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.exceptions import ImproperlyConfigured
from django.test import RequestFactory, SimpleTestCase, TestCase, override_settings
from django.urls import clear_url_caches
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import UserProfile, UserRole
from config import sentry
from config.admin_path import admin_url_path
from config.client_ip import client_ip

User = get_user_model()
TEST_API_KEY = "test-key"
# What Render's proxy looks like to the app: the same internal address on
# every request, whoever the client is.
PROXY_ADDR = "10.201.4.7"


def _forwarded(ip, spoofed=None):
    value = f"{spoofed}, {ip}" if spoofed else ip
    return {"REMOTE_ADDR": PROXY_ADDR, "HTTP_X_FORWARDED_FOR": value}


class ClientIpTests(SimpleTestCase):
    def setUp(self):
        self.factory = RequestFactory()

    def _ip(self, **meta):
        return client_ip(self.factory.get("/", **meta))

    @override_settings(TRUSTED_PROXY_HOPS=1)
    def test_behind_one_proxy_the_entry_it_appended_is_the_client(self):
        self.assertEqual(self._ip(**_forwarded("203.0.113.5")), "203.0.113.5")

    @override_settings(TRUSTED_PROXY_HOPS=1)
    def test_a_client_supplied_x_forwarded_for_is_ignored(self):
        # The client sent "X-Forwarded-For: 1.2.3.4"; Render appended the real address.
        self.assertEqual(self._ip(**_forwarded("203.0.113.5", spoofed="1.2.3.4")), "203.0.113.5")

    @override_settings(TRUSTED_PROXY_HOPS=2)
    def test_two_proxies_skip_the_second_proxys_entry(self):
        meta = {"REMOTE_ADDR": PROXY_ADDR, "HTTP_X_FORWARDED_FOR": "1.2.3.4, 203.0.113.5, 172.16.0.9"}
        self.assertEqual(self._ip(**meta), "203.0.113.5")

    @override_settings(TRUSTED_PROXY_HOPS=0)
    def test_not_behind_a_proxy_the_header_is_never_trusted(self):
        self.assertEqual(self._ip(**_forwarded("203.0.113.5")), PROXY_ADDR)

    @override_settings(TRUSTED_PROXY_HOPS=1)
    def test_a_missing_or_malformed_header_falls_back_to_the_connecting_address(self):
        self.assertEqual(self._ip(REMOTE_ADDR=PROXY_ADDR), PROXY_ADDR)
        self.assertEqual(self._ip(REMOTE_ADDR=PROXY_ADDR, HTTP_X_FORWARDED_FOR="not-an-ip"), PROXY_ADDR)

    @override_settings(TRUSTED_PROXY_HOPS=1)
    def test_ipv6_clients_are_read_too(self):
        self.assertEqual(self._ip(**_forwarded("2001:db8::1")), "2001:db8::1")


class _RateLimitTestCase(TestCase):
    def setUp(self):
        # django-ratelimit's counters live in the real Redis cache; clear only its own keys (see accounts.tests).
        cache.delete_pattern("rl:*")

    def tearDown(self):
        cache.delete_pattern("rl:*")


@override_settings(API_KEY=TEST_API_KEY, TRUSTED_PROXY_HOPS=1)
class PerClientRateLimitTests(_RateLimitTestCase):
    """Behind Render every request arrives from the proxy's address; limits
    must still be per client, not one bucket for everyone."""

    def _refresh(self, ip, spoofed=None):
        # An invalid token still counts against the limit (and answers 401 quickly).
        return self.client.post(
            "/api/accounts/token/refresh/", {"refresh": "not-a-token"}, content_type="application/json",
            HTTP_X_API_KEY=TEST_API_KEY, **_forwarded(ip, spoofed),
        )

    def test_two_client_ips_behind_the_same_proxy_get_separate_limits(self):
        for _ in range(30):
            self.assertEqual(self._refresh("203.0.113.5").status_code, 401)
        self.assertEqual(self._refresh("203.0.113.5").status_code, 429)

        # A different person behind the same Render proxy is unaffected.
        self.assertEqual(self._refresh("198.51.100.20").status_code, 401)

    def test_a_spoofed_x_forwarded_for_does_not_get_a_fresh_limit(self):
        for i in range(30):
            self._refresh("203.0.113.5", spoofed=f"1.2.3.{i}")
        self.assertEqual(self._refresh("203.0.113.5", spoofed="9.9.9.9").status_code, 429)


@override_settings(API_KEY=TEST_API_KEY, TRUSTED_PROXY_HOPS=1)
class PerUserRateLimitTests(_RateLimitTestCase):
    def _user(self, email):
        user = User.objects.create_user(username=email, email=email)
        UserProfile.objects.create(user=user, role=UserRole.CUSTOMER, full_name="Test User")
        return user

    def _delete_without_confirm(self, user):
        # Missing confirm word: answers 400 and deletes nothing, but counts against the 5/h limit.
        return self.client.post(
            "/api/accounts/delete/", {}, content_type="application/json",
            HTTP_X_API_KEY=TEST_API_KEY, HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}",
            **_forwarded("203.0.113.5"),
        )

    def test_signed_in_users_on_the_same_ip_get_separate_limits(self):
        first, second = self._user("one@example.com"), self._user("two@example.com")
        for _ in range(5):
            self.assertEqual(self._delete_without_confirm(first).status_code, 400)
        self.assertEqual(self._delete_without_confirm(first).status_code, 429)
        self.assertEqual(self._delete_without_confirm(second).status_code, 400)


class AdminUrlPathTests(SimpleTestCase):
    def test_unset_uses_admin_only_in_debug(self):
        self.assertEqual(admin_url_path(None, debug=True), "admin/")
        self.assertEqual(admin_url_path("  ", debug=True), "admin/")
        with self.assertRaises(ImproperlyConfigured):
            admin_url_path(None, debug=False)

    def test_a_set_path_is_normalised(self):
        self.assertEqual(admin_url_path("/manage-x7k2/", debug=False), "manage-x7k2/")
        self.assertEqual(admin_url_path("ops/manage-x7k2", debug=False), "ops/manage-x7k2/")

    def test_well_known_or_odd_paths_are_refused_in_production(self):
        for bad in ("admin", "Admin/", "api"):
            with self.assertRaises(ImproperlyConfigured):
                admin_url_path(bad, debug=False)
        for bad in ("man age", "x/../y", "a?b"):
            with self.assertRaises(ImproperlyConfigured):
                admin_url_path(bad, debug=True)


class AdminMountedAtConfiguredPathTests(TestCase):
    def setUp(self):
        self._reload_urls("manage-test-9q2/")

    def tearDown(self):
        self._reload_urls(settings.ADMIN_URL_PATH)

    def _reload_urls(self, admin_path):
        with override_settings(ADMIN_URL_PATH=admin_path):
            import config.urls

            importlib.reload(config.urls)
        clear_url_caches()

    def test_the_admin_is_served_only_at_the_configured_path(self):
        self.assertEqual(self.client.get("/manage-test-9q2/login/").status_code, 200)
        self.assertEqual(self.client.get("/admin/login/").status_code, 404)


@override_settings(TRUSTED_PROXY_HOPS=1)
class AdminLoginRateLimitTests(_RateLimitTestCase):
    def _login(self, ip, username="staff@example.com"):
        return self.client.post(
            f"/{settings.ADMIN_URL_PATH}login/", {"username": username, "password": "wrong"}, **_forwarded(ip)
        )

    def test_login_attempts_are_limited_per_client_ip(self):
        for i in range(5):
            # A wrong password re-shows the form (200); different usernames so only the IP limit applies.
            self.assertEqual(self._login("203.0.113.5", username=f"user{i}").status_code, 200)
        self.assertEqual(self._login("203.0.113.5", username="user9").status_code, 429)
        self.assertEqual(self._login("198.51.100.20").status_code, 200)

    def test_login_attempts_on_one_username_are_limited_across_ips(self):
        for i in range(10):
            self.assertEqual(self._login(f"203.0.113.{i}", username="Staff@Example.com").status_code, 200)
        self.assertEqual(self._login("198.51.100.20", username="staff@example.com").status_code, 429)

    def test_a_correct_login_still_works(self):
        User.objects.create_superuser("boss", "boss@example.com", "S3cure-Passphrase-2026")
        response = self.client.post(
            f"/{settings.ADMIN_URL_PATH}login/", {"username": "boss", "password": "S3cure-Passphrase-2026"},
            **_forwarded("203.0.113.5"),
        )
        self.assertEqual(response.status_code, 302)


class SentryScrubbingTests(SimpleTestCase):
    def test_request_keeps_only_method_and_path(self):
        event = {"request": {
            "method": "POST", "url": "https://x.onrender.com/api/messages/?q=plumber",
            "data": {"body": "My number is 780 555 0100"}, "cookies": {"sessionid": "abc"},
            "headers": {"Authorization": "Bearer eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyIjoxfQ.sig", "X-Api-Key": "k"},
            "query_string": "q=plumber", "env": {"REMOTE_ADDR": "203.0.113.5"},
        }}
        scrubbed = sentry.before_send(event, None)
        self.assertEqual(scrubbed["request"], {"method": "POST", "url": "https://x.onrender.com/api/messages/"})

    def test_user_extra_and_local_variables_are_dropped(self):
        event = {
            "user": {"email": "a@example.com", "ip_address": "203.0.113.5"},
            "extra": {"body": "hello"},
            "exception": {"values": [{"type": "ValueError", "value": "bad", "stacktrace": {
                "frames": [{"function": "post", "vars": {"text": "private chat message"}}]}}]},
        }
        scrubbed = sentry.before_send(event, None)
        self.assertNotIn("user", scrubbed)
        self.assertNotIn("extra", scrubbed)
        self.assertNotIn("vars", scrubbed["exception"]["values"][0]["stacktrace"]["frames"][0])

    def test_personal_data_in_error_messages_is_replaced(self):
        value = (
            'duplicate key: Key (email)=(jane.doe@example.com) already exists; phone +1 (780) 555-0100; '
            "token eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjo0Mn0.c2lnbmF0dXJlLXZhbHVl; "
            "Authorization: Bearer abc.def; fcm dK3x9Qz7Lm2Np4Rs6Tv8Wy0Ab1Cd3Ef5"
        )
        event = {
            "exception": {"values": [{"type": "IntegrityError", "value": value}]},
            "logentry": {"message": "Push failed for %s", "params": ["jane.doe@example.com"]},
        }
        scrubbed = sentry.before_send(event, None)
        text = scrubbed["exception"]["values"][0]["value"]
        for secret in ("jane.doe", "555-0100", "eyJhbGci", "abc.def", "dK3x9Qz7"):
            self.assertNotIn(secret, text)
        self.assertIn("IntegrityError", scrubbed["exception"]["values"][0]["type"])
        self.assertNotIn("params", scrubbed["logentry"])

    def test_breadcrumbs_lose_their_data(self):
        crumb = {"category": "query", "message": "SELECT ... WHERE email = 'a@example.com'",
                 "data": {"params": ["a@example.com"]}, "type": "default"}
        scrubbed = sentry.before_breadcrumb(crumb, None)
        self.assertNotIn("data", scrubbed)
        self.assertNotIn("a@example.com", scrubbed["message"])
        self.assertEqual(scrubbed["category"], "query")
