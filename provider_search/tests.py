from unittest.mock import patch

from django.test import TestCase, override_settings

from catalog.models import Service

from .models import ProviderOnboarding, ServiceRequest

TEST_API_KEY = "test-key"


@override_settings(API_KEY=TEST_API_KEY)
class ChatRefineViewTests(TestCase):
    """POST /api/chat/refine/ — classification only, no request is created
    here (see ServiceRequestCreateViewTests for that)."""

    def setUp(self):
        self.headers = {"HTTP_X_API_KEY": TEST_API_KEY}

    def _refine(self, **body):
        return self.client.post("/api/chat/refine/", body, content_type="application/json", **self.headers)

    def test_classifies_free_text_into_a_category(self):
        response = self._refine(message="my kitchen sink is leaking", device_id="dev-1")
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["category"], "plumbing")
        self.assertIn("urgency", body)
        self.assertIn("notes", body)

    def test_unclassifiable_text_returns_a_null_category_not_an_error(self):
        # Forces the deterministic keyword-fallback path (see chat_service.
        # refine_request, which itself falls back to matching_engine.
        # ai_categorize) rather than depending on what the real Claude API
        # happens to guess for nonsense text.
        with (
            patch("provider_search.chat_service._refine_with_llm", side_effect=RuntimeError("no LLM in this test")),
            patch("matching.matching_engine._ai_categorize_llm", side_effect=RuntimeError("no LLM in this test")),
        ):
            response = self._refine(message="zzzz qqqq", device_id="dev-1")
        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.json()["category"])

    def test_reports_whether_the_category_is_launched(self):
        launched = self._refine(message="my kitchen sink is leaking", device_id="dev-1").json()
        self.assertTrue(launched["launched"])
        coming_soon = self._refine(message="need someone to mow my lawn", device_id="dev-1").json()
        self.assertEqual(coming_soon["category"], "lawn-care")
        self.assertFalse(coming_soon["launched"])

    def test_never_creates_a_service_request(self):
        self._refine(message="my kitchen sink is leaking", device_id="dev-1")
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_message_is_required(self):
        self.assertEqual(self._refine(device_id="dev-1").status_code, 400)
        self.assertEqual(self._refine(message="   ", device_id="dev-1").status_code, 400)

    def test_device_id_is_required(self):
        self.assertEqual(self._refine(message="a leaking pipe").status_code, 400)

    def test_it_requires_the_api_key(self):
        response = self.client.post(
            "/api/chat/refine/", {"message": "x", "device_id": "dev-1"}, content_type="application/json"
        )
        self.assertEqual(response.status_code, 401)


@override_settings(API_KEY=TEST_API_KEY)
class ServiceRequestCreateViewTests(TestCase):
    """POST /api/requests/ — the only way a ServiceRequest is created, by the
    app's own request flow today and (once it exists) the website form.
    Replaces the old Google-listing search+unlock flow entirely."""

    def setUp(self):
        self.headers = {"HTTP_X_API_KEY": TEST_API_KEY}

    def _create(self, **overrides):
        body = {
            "device_id": "dev-1",
            "category": "plumbing",
            "phone": "+1 780-555-0100",
            "city": "Edmonton",
            "consent": True,
            **overrides,
        }
        return self.client.post("/api/requests/", body, content_type="application/json", **self.headers)

    def test_creates_a_service_request_with_consent_recorded(self):
        response = self._create()
        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertEqual(body["category"], "plumbing")
        self.assertIn("request_id", body)

        request = ServiceRequest.objects.get(id=body["request_id"])
        self.assertEqual(request.device_id, "dev-1")
        self.assertEqual(request.category, "plumbing")
        self.assertEqual(request.city, "Edmonton")
        self.assertEqual(request.phone, "+1 780-555-0100")
        self.assertTrue(request.consent_given)

    def test_optional_description_is_stored_as_problem_description(self):
        response = self._create(description="Leaking under the sink")
        request = ServiceRequest.objects.get(id=response.json()["request_id"])
        self.assertEqual(request.problem_description, "Leaking under the sink")

    def test_description_is_optional(self):
        response = self._create()
        self.assertEqual(response.status_code, 201)
        request = ServiceRequest.objects.get(id=response.json()["request_id"])
        self.assertEqual(request.problem_description, "")

    def test_city_defaults_to_edmonton_when_not_given(self):
        body = {"device_id": "dev-1", "category": "plumbing", "phone": "+1 780-555-0100", "consent": True}
        response = self.client.post("/api/requests/", body, content_type="application/json", **self.headers)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(ServiceRequest.objects.get().city, "Edmonton")

    # ---- The category must be a real catalog service; launch state decides status ----

    def test_a_launched_service_is_created_as_new(self):
        body = self._create().json()
        self.assertEqual(body["status"], ServiceRequest.STATUS_NEW)
        self.assertNotIn("message", body)
        self.assertEqual(ServiceRequest.objects.get().status, ServiceRequest.STATUS_NEW)

    def test_a_not_yet_launched_service_is_waitlisted_with_a_coming_soon_message(self):
        response = self._create(category="lawn-care")
        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertEqual(body["status"], ServiceRequest.STATUS_WAITLISTED)
        self.assertEqual(body["message"], "Coming soon in your area")
        request = ServiceRequest.objects.get(id=body["request_id"])
        self.assertEqual(request.status, ServiceRequest.STATUS_WAITLISTED)
        self.assertEqual(request.category, "lawn-care")
        self.assertTrue(request.consent_given)

    def test_launching_the_service_makes_new_requests_normal(self):
        Service.objects.filter(slug="lawn-care").update(is_launched=True)
        self.assertEqual(self._create(category="lawn-care").json()["status"], ServiceRequest.STATUS_NEW)

    def test_an_unknown_category_is_rejected(self):
        for bad in ("not-a-service", "Plumbing", ["plumbing"], 7):
            with self.subTest(category=bad):
                self.assertEqual(self._create(category=bad).status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_an_inactive_service_is_rejected_not_waitlisted(self):
        Service.objects.filter(slug="plumbing").update(is_active=False)
        self.assertEqual(self._create().status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_waitlisted_requests_still_need_phone_and_consent(self):
        self.assertEqual(self._create(category="lawn-care", consent=False).status_code, 400)
        self.assertEqual(self._create(category="lawn-care", phone="").status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    # ---- Explicit consent is mandatory — never defaulted, never inferred ----

    def test_without_consent_nothing_is_created(self):
        for missing_consent in (False, None, "yes", 1):
            with self.subTest(consent=missing_consent):
                response = self._create(consent=missing_consent, device_id=f"dev-{missing_consent}")
                self.assertEqual(response.status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_consent_omitted_entirely_is_also_rejected(self):
        body = {"device_id": "dev-1", "category": "plumbing", "phone": "+1 780-555-0100"}
        response = self.client.post("/api/requests/", body, content_type="application/json", **self.headers)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    # ---- Required fields ----

    def test_device_id_is_required(self):
        response = self._create(device_id="")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_category_is_required(self):
        response = self._create(category="")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_phone_is_required(self):
        response = self._create(phone="")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_phone_that_is_only_whitespace_is_rejected(self):
        response = self._create(phone="   ")
        self.assertEqual(response.status_code, 400)

    def test_city_must_be_a_served_city(self):
        response = self._create(city="Toronto")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_it_requires_the_api_key(self):
        body = {"device_id": "dev-1", "category": "plumbing", "phone": "+1 780-555-0100", "consent": True}
        response = self.client.post("/api/requests/", body, content_type="application/json")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(ServiceRequest.objects.count(), 0)


@override_settings(API_KEY=TEST_API_KEY)
class ServiceRequestListViewTests(TestCase):
    """GET /api/requests/mine/ — "Your requests"."""

    def setUp(self):
        self.headers = {"HTTP_X_API_KEY": TEST_API_KEY}

    def _make(self, device_id="dev-1", **fields):
        return ServiceRequest.objects.create(
            device_id=device_id,
            category=fields.pop("category", "plumbing"),
            city=fields.pop("city", "Edmonton"),
            phone=fields.pop("phone", "+1 780-555-0100"),
            consent_given=True,
            **fields,
        )

    def test_lists_only_this_devices_requests_newest_first(self):
        self._make(device_id="dev-1", category="plumbing")
        newest = self._make(device_id="dev-1", category="electrical")
        self._make(device_id="dev-2", category="roofing")  # a different device

        response = self.client.get("/api/requests/mine/", {"device_id": "dev-1"}, **self.headers)
        self.assertEqual(response.status_code, 200)
        results = response.json()["requests"]
        self.assertEqual(len(results), 2)
        self.assertEqual(results[0]["id"], newest.id)

    def test_a_device_with_no_requests_gets_an_empty_list_not_an_error(self):
        response = self.client.get("/api/requests/mine/", {"device_id": "nobody"}, **self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["requests"], [])

    def test_includes_phone_since_its_the_devices_own_data(self):
        self._make(phone="+1 780-555-0199")
        results = self.client.get("/api/requests/mine/", {"device_id": "dev-1"}, **self.headers).json()["requests"]
        self.assertEqual(results[0]["phone"], "+1 780-555-0199")

    def test_device_id_is_required(self):
        response = self.client.get("/api/requests/mine/", **self.headers)
        self.assertEqual(response.status_code, 400)

    def test_it_requires_the_api_key(self):
        response = self.client.get("/api/requests/mine/", {"device_id": "dev-1"})
        self.assertEqual(response.status_code, 401)


@override_settings(API_KEY=TEST_API_KEY)
class ProviderOnboardingViewTests(TestCase):
    """Untouched by the Google-listing/paywall removal — a quick smoke test
    that it still works now that provider_search.views was rewritten."""

    def setUp(self):
        self.headers = {"HTTP_X_API_KEY": TEST_API_KEY}

    def test_get_creates_and_returns_a_blank_onboarding_record(self):
        response = self.client.get("/api/provider-onboarding/", {"provider_id": "prov-1"}, **self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["completion_percentage"], 0)
        self.assertTrue(ProviderOnboarding.objects.filter(provider_id="prov-1").exists())

    def test_post_updates_one_section(self):
        self.client.get("/api/provider-onboarding/", {"provider_id": "prov-1"}, **self.headers)
        response = self.client.post(
            "/api/provider-onboarding/",
            {"provider_id": "prov-1", "section": "service_area", "fields": {"city": "Calgary"}},
            content_type="application/json",
            **self.headers,
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(ProviderOnboarding.objects.get(provider_id="prov-1").city, "Calgary")


@override_settings(API_KEY=TEST_API_KEY)
class RequestEndpointAuthTests(TestCase):
    """POST /api/requests/ is gated by the shared API key and nothing else —
    there are no user accounts, so it must never ask for a login — and a
    rejected key says so (it used to answer "Authentication credentials were
    not provided.", which sounds like a missing login)."""

    BODY = {"device_id": "dev-1", "category": "plumbing", "phone": "+1 780-555-0100", "consent": True}

    def _post(self, **headers):
        return self.client.post("/api/requests/", self.BODY, content_type="application/json", **headers)

    def test_the_api_key_alone_is_enough_no_login_needed(self):
        response = self._post(HTTP_X_API_KEY=TEST_API_KEY)
        self.assertEqual(response.status_code, 201)
        self.assertNotIn("HTTP_AUTHORIZATION", response.wsgi_request.META)

    def test_it_uses_the_project_wide_auth_defaults_and_adds_nothing(self):
        from rest_framework.settings import api_settings

        from .views import ServiceRequestCreateView

        self.assertEqual(ServiceRequestCreateView.permission_classes, api_settings.DEFAULT_PERMISSION_CLASSES)
        self.assertEqual(ServiceRequestCreateView.authentication_classes, api_settings.DEFAULT_AUTHENTICATION_CLASSES)

    def test_a_missing_or_wrong_key_is_rejected_and_names_the_key(self):
        cases = {
            "no key": {},
            "wrong key": {"HTTP_X_API_KEY": "not-the-key"},
            "key with a trailing newline": {"HTTP_X_API_KEY": TEST_API_KEY + chr(10)},
            "key with a leading space": {"HTTP_X_API_KEY": " " + TEST_API_KEY},
            "empty key": {"HTTP_X_API_KEY": ""},
        }
        for name, headers in cases.items():
            with self.subTest(name):
                response = self._post(**headers)
                self.assertEqual(response.status_code, 401)
                self.assertEqual(response.json(), {"detail": "Missing or invalid API key."})
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_a_non_ascii_key_is_rejected_not_a_server_error(self):
        response = self._post(HTTP_X_API_KEY="kéy")
        self.assertEqual(response.status_code, 401)

    def test_a_bad_key_is_rejected_the_same_way_on_the_endpoints_that_work(self):
        # The app's other calls go through the same gate, so a key problem
        # shows up everywhere, not only on submit.
        for path in ("/api/requests/mine/?device_id=d", "/api/catalog/categories/"):
            with self.subTest(path):
                response = self.client.get(path, HTTP_X_API_KEY="not-the-key")
                self.assertEqual(response.status_code, 401)
                self.assertEqual(response.json(), {"detail": "Missing or invalid API key."})
