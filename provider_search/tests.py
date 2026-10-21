from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import UserProfile, UserRole
from catalog.models import Service
from leads.models import LeadOffer
from providers.models import ProviderProfile

from .models import ProviderOnboarding, ServiceRequest

TEST_API_KEY = "test-key"


def signed_in(email="client@example.com", role=UserRole.CUSTOMER, name="Pat Client"):
    """(user, request headers) for a signed-in account: the API key plus its token."""
    user = get_user_model().objects.create_user(username=email, email=email)
    UserProfile.objects.create(user=user, role=role, full_name=name)
    token = RefreshToken.for_user(user).access_token
    return user, {"HTTP_X_API_KEY": TEST_API_KEY, "HTTP_AUTHORIZATION": f"Bearer {token}"}


def make_provider(name="Ace Plumbing", email="ace@example.com"):
    user, headers = signed_in(email, UserRole.PROVIDER, f"Owner of {name}")
    profile = ProviderProfile.objects.create(
        user=user, business_name=name, phone="+17805550101", email=email, status=ProviderProfile.STATUS_APPROVED
    )
    return profile, headers


def make_offer(service_request, provider, status=LeadOffer.STATUS_ACCEPTED):
    from django.utils import timezone

    offer = LeadOffer.objects.create(service_request=service_request, provider=provider)
    offer.status = status
    offer.sent_at = offer.responded_at = timezone.now()
    offer.save()
    return offer


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
    Replaces the old Google-listing search+unlock flow entirely. Needs a
    signed-in client: the request belongs to that account."""

    def setUp(self):
        self.client_user, self.headers = signed_in()

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
        self.assertEqual(request.phone, "+17805550100")  # stored as E.164
        self.assertTrue(request.consent_given)

    def test_optional_description_is_stored_as_problem_description(self):
        response = self._create(description="Leaking under the sink")
        request = ServiceRequest.objects.get(id=response.json()["request_id"])
        self.assertEqual(request.problem_description, "Leaking under the sink")

    def test_urgency_is_stored_so_it_can_go_in_the_message_to_providers(self):
        for value in ("today", "this_week", "exploring"):
            with self.subTest(urgency=value):
                response = self._create(urgency=value, device_id=f"dev-{value}")
                self.assertEqual(ServiceRequest.objects.get(id=response.json()["request_id"]).urgency, value)

    def test_a_missing_or_unknown_urgency_is_stored_blank_not_rejected(self):
        for value in (None, "", "yesterday", 5):
            with self.subTest(urgency=value):
                response = self._create(urgency=value, device_id=f"dev-{value}")
                self.assertEqual(response.status_code, 201)
                self.assertEqual(ServiceRequest.objects.get(id=response.json()["request_id"]).urgency, "")

    def test_description_is_optional(self):
        response = self._create()
        self.assertEqual(response.status_code, 201)
        request = ServiceRequest.objects.get(id=response.json()["request_id"])
        self.assertEqual(request.problem_description, "")

    def test_location_is_stored_trimmed_and_is_optional(self):
        response = self._create(location="  T5J   0N3 ")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(ServiceRequest.objects.get(id=response.json()["request_id"]).location, "T5J 0N3")
        blank = self._create(device_id="dev-2")
        self.assertEqual(ServiceRequest.objects.get(id=blank.json()["request_id"]).location, "")

    def test_an_address_is_accepted_as_the_location(self):
        response = self._create(location="10123 99 Street NW, Edmonton")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(ServiceRequest.objects.get().location, "10123 99 Street NW, Edmonton")

    def test_a_location_that_is_not_text_or_is_too_long_is_refused(self):
        for bad in (["T5J 0N3"], {"lat": 53.5}, 53.5, "x" * 121):
            with self.subTest(bad=bad):
                self.assertEqual(self._create(location=bad).status_code, 400)
        self.assertFalse(ServiceRequest.objects.exists())

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
        self.assertEqual(
            body["message"],
            "This service is coming soon in your area. We saved your request and will contact you when it opens.",
        )
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

    def test_device_id_is_optional_now_that_the_account_identifies_the_client(self):
        body = {"category": "plumbing", "phone": "+1 780-555-0100", "consent": True}
        response = self.client.post("/api/requests/", body, content_type="application/json", **self.headers)
        self.assertEqual(response.status_code, 201)
        request = ServiceRequest.objects.get()
        self.assertEqual(request.device_id, "")
        self.assertEqual(request.user, self.client_user)

    def test_the_request_belongs_to_the_signed_in_client(self):
        self.assertEqual(self._create().status_code, 201)
        self.assertEqual(ServiceRequest.objects.get().user, self.client_user)

    def test_a_very_long_device_id_is_trimmed_not_rejected(self):
        self.assertEqual(self._create(device_id="x" * 200).status_code, 201)
        self.assertEqual(len(ServiceRequest.objects.get().device_id), 64)

    def test_category_is_required(self):
        response = self._create(category="")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_phone_is_required(self):
        response = self._create(phone="")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    # ---- The client's phone must be a Canadian / North American number ----

    INVALID_PHONE = "Enter a valid Canadian or North American phone number, for example 780 555 0100."

    def test_valid_numbers_are_stored_as_e164_whatever_the_formatting(self):
        for raw in ("780 555 0100", "(780) 555-0100", "780.555.0100", "1-780-555-0100",
                    "17805550100", "+1 780 555 0100", "+17805550100", "  780-555-0100  "):
            with self.subTest(phone=raw):
                response = self._create(phone=raw, device_id=f"dev-{raw}")
                self.assertEqual(response.status_code, 201)
                self.assertEqual(ServiceRequest.objects.get(id=response.json()["request_id"]).phone, "+17805550100")

    def test_an_eleven_digit_number_not_starting_with_1_is_rejected(self):
        response = self._create(phone="58792199587")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json(), {"detail": self.INVALID_PHONE})
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_numbers_that_are_not_north_american_are_rejected(self):
        bad = {
            "too short": "555 0100",
            "nine digits": "780555010",
            "twelve digits": "178055501001",
            "another country": "+44 20 7946 0958",
            "area code starts with 1": "1234567890",
            "area code starts with 0": "0805550100",
            "exchange starts with 1": "7801550100",
            "letters": "780-555-CALL",
            "an extension": "780 555 0100 ext 5",
            "two plus signs": "++17805550100",
            "plus in the middle": "780+5550100",
            "punctuation only": "()-.",
        }
        for label, raw in bad.items():
            with self.subTest(label):
                response = self._create(phone=raw, device_id=f"dev-{label}")
                self.assertEqual(response.status_code, 400, raw)
                self.assertEqual(response.json(), {"detail": self.INVALID_PHONE})
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_a_phone_that_is_not_a_string_is_rejected_not_a_server_error(self):
        for value in (7805550100, ["780 555 0100"], {"n": "780 555 0100"}, True):
            with self.subTest(phone=value):
                self.assertEqual(self._create(phone=value, device_id=f"dev-{value}").status_code, 400)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_a_bad_phone_is_rejected_for_waitlisted_services_too(self):
        response = self._create(category="lawn-care", phone="58792199587")
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
    """GET /api/requests/mine/: "Your requests", for the signed-in client only.
    The old device_id listing made a phone number readable to whoever held
    that id; it is gone."""

    def setUp(self):
        self.user, self.headers = signed_in()

    def _make(self, user=None, **fields):
        return ServiceRequest.objects.create(
            user=user or self.user,
            device_id=fields.pop("device_id", "dev-1"),
            category=fields.pop("category", "plumbing"),
            city=fields.pop("city", "Edmonton"),
            phone=fields.pop("phone", "+1 780-555-0100"),
            consent_given=True,
            **fields,
        )

    def test_lists_only_this_accounts_requests_newest_first(self):
        self._make(category="plumbing")
        newest = self._make(category="electrical")
        other, _ = signed_in("other@example.com")
        self._make(user=other, category="roofing")  # someone else's

        response = self.client.get("/api/requests/mine/", **self.headers)
        self.assertEqual(response.status_code, 200)
        results = response.json()["requests"]
        self.assertEqual(len(results), 2)
        self.assertEqual(results[0]["id"], newest.id)

    def test_an_account_with_no_requests_gets_an_empty_list_not_an_error(self):
        response = self.client.get("/api/requests/mine/", **self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["requests"], [])

    def test_includes_the_owners_own_phone_and_urgency(self):
        self._make(phone="+1 780-555-0199", urgency="today")
        (result,) = self.client.get("/api/requests/mine/", **self.headers).json()["requests"]
        self.assertEqual(result["phone"], "+1 780-555-0199")
        self.assertEqual(result["urgency"], "today")

    def test_a_device_id_in_the_url_is_ignored_so_it_cannot_be_used_to_read_anyones_requests(self):
        owner, _ = signed_in("owner@example.com")
        self._make(user=owner, device_id="victim-device", phone="+1 780-555-0177")
        # Another signed-in client who knows the device id still sees nothing of it.
        response = self.client.get("/api/requests/mine/", {"device_id": "victim-device"}, **self.headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["requests"], [])
        self.assertNotIn("0177", response.content.decode())

    def test_without_signing_in_nothing_is_readable_even_with_a_valid_device_id(self):
        self._make(device_id="dev-1", phone="+1 780-555-0188")
        for params in ({}, {"device_id": "dev-1"}):
            response = self.client.get("/api/requests/mine/", params, HTTP_X_API_KEY=TEST_API_KEY)
            self.assertEqual(response.status_code, 401, params)
            self.assertNotIn("0188", response.content.decode())

    def test_a_provider_account_cannot_use_the_clients_list(self):
        _, provider_headers = signed_in("pro@example.com", UserRole.PROVIDER)
        self.assertEqual(self.client.get("/api/requests/mine/", **provider_headers).status_code, 403)

    def test_it_requires_the_api_key_even_with_a_valid_login(self):
        response = self.client.get("/api/requests/mine/", HTTP_AUTHORIZATION=self.headers["HTTP_AUTHORIZATION"])
        self.assertEqual(response.status_code, 403)  # signed in, but the key check fails
        self.assertEqual(response.json(), {"detail": "Missing or invalid API key."})

    def test_it_shows_who_accepted_and_whether_the_job_can_be_marked_complete(self):
        request = self._make()
        ace, _ = make_provider("Ace Plumbing", "ace@example.com")
        busy, _ = make_provider("Busy Pipes", "busy@example.com")
        make_offer(request, ace, LeadOffer.STATUS_ACCEPTED)
        make_offer(request, busy, LeadOffer.STATUS_DECLINED)  # not shown: only YES replies are
        (result,) = self.client.get("/api/requests/mine/", **self.headers).json()["requests"]
        (accepted,) = result["accepted_offers"]
        self.assertEqual(accepted["provider"]["business_name"], "Ace Plumbing")
        self.assertTrue(accepted["can_complete"])
        self.assertFalse(accepted["job_completed"])


@override_settings(API_KEY=TEST_API_KEY)
class ServiceRequestCompleteViewTests(TestCase):
    """POST /api/requests/<id>/complete/: only the request's own client, only
    for a provider who accepted, only once."""

    def setUp(self):
        self.user, self.headers = signed_in()
        self.request = ServiceRequest.objects.create(
            user=self.user, category="plumbing", city="Edmonton", phone="+17805550100", consent_given=True
        )
        self.provider, self.provider_headers = make_provider()
        self.offer = make_offer(self.request, self.provider)

    def _complete(self, headers=None, request_id=None, **body):
        body = {"offer_id": self.offer.id, **body}
        return self.client.post(
            f"/api/requests/{request_id or self.request.id}/complete/", body,
            content_type="application/json", **(headers or self.headers),
        )

    def test_the_client_marks_the_job_complete_with_the_provider_who_accepted(self):
        response = self._complete()
        self.assertEqual(response.status_code, 200)
        self.offer.refresh_from_db()
        self.assertTrue(self.offer.hired and self.offer.job_completed)
        self.assertIsNotNone(self.offer.hired_at)
        self.assertIsNotNone(self.offer.completed_at)
        (accepted,) = response.json()["accepted_offers"]
        self.assertTrue(accepted["job_completed"])
        self.assertFalse(accepted["can_complete"])

    def test_another_client_cannot_complete_it_and_cannot_tell_it_exists(self):
        _, stranger = signed_in("stranger@example.com")
        response = self._complete(headers=stranger)
        self.assertEqual(response.status_code, 404)
        self.offer.refresh_from_db()
        self.assertFalse(self.offer.job_completed)

    def test_the_provider_cannot_complete_their_own_job(self):
        response = self._complete(headers=self.provider_headers)
        self.assertEqual(response.status_code, 403)
        self.offer.refresh_from_db()
        self.assertFalse(self.offer.job_completed)

    def test_signing_in_and_the_api_key_are_both_required(self):
        self.assertEqual(self._complete(headers={"HTTP_X_API_KEY": TEST_API_KEY}).status_code, 401)
        no_key = {"HTTP_AUTHORIZATION": self.headers["HTTP_AUTHORIZATION"]}
        self.assertEqual(self._complete(headers=no_key).status_code, 403)

    def test_only_an_accepted_offer_can_be_completed(self):
        for status in (LeadOffer.STATUS_SENT, LeadOffer.STATUS_DECLINED, LeadOffer.STATUS_EXPIRED):
            with self.subTest(status=status):
                other, _ = make_provider(f"P {status}", f"{status}@example.com")
                offer = make_offer(self.request, other, status)
                self.assertEqual(self._complete(offer_id=offer.id).status_code, 400)
                offer.refresh_from_db()
                self.assertFalse(offer.job_completed)

    def test_an_offer_from_someone_elses_request_is_refused(self):
        other_user, _ = signed_in("other@example.com")
        other_request = ServiceRequest.objects.create(
            user=other_user, category="plumbing", city="Edmonton", phone="+17805550102", consent_given=True
        )
        foreign = make_offer(other_request, self.provider)
        self.assertEqual(self._complete(offer_id=foreign.id).status_code, 400)
        foreign.refresh_from_db()
        self.assertFalse(foreign.job_completed)

    def test_a_missing_or_malformed_offer_id_is_a_400_not_a_server_error(self):
        for value in (None, "abc", True, [1], {"a": 1}, 999999):
            with self.subTest(offer_id=value):
                self.assertEqual(self._complete(offer_id=value).status_code, 400)

    def test_a_request_can_only_be_completed_once(self):
        second, _ = make_provider("Second Co", "second@example.com")
        other_offer = make_offer(self.request, second)
        self.assertEqual(self._complete().status_code, 200)
        self.assertEqual(self._complete(offer_id=other_offer.id).status_code, 409)
        self.assertEqual(self._complete().status_code, 409)  # not repeatable either
        other_offer.refresh_from_db()
        self.assertFalse(other_offer.job_completed)

    def test_an_unknown_request_is_a_404(self):
        self.assertEqual(self._complete(request_id=999999).status_code, 404)


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
    """POST /api/requests/ needs the shared API key AND a signed-in client. A
    rejected key says so ("Missing or invalid API key."); a missing login says
    that instead, so the two problems are never confused."""

    BODY = {"category": "plumbing", "phone": "+1 780-555-0100", "consent": True}

    def setUp(self):
        self.user, self.signed_in_headers = signed_in()

    def _post(self, **headers):
        return self.client.post("/api/requests/", self.BODY, content_type="application/json", **headers)

    def test_the_key_and_a_client_login_are_both_needed(self):
        self.assertEqual(self._post(**self.signed_in_headers).status_code, 201)

    def test_the_key_alone_is_no_longer_enough(self):
        response = self._post(HTTP_X_API_KEY=TEST_API_KEY)
        self.assertEqual(response.status_code, 401)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_a_login_alone_is_not_enough_either(self):
        response = self._post(HTTP_AUTHORIZATION=self.signed_in_headers["HTTP_AUTHORIZATION"])
        self.assertEqual(response.status_code, 403)  # signed in, but the key check fails
        self.assertEqual(response.json(), {"detail": "Missing or invalid API key."})

    def test_only_a_client_account_may_submit_a_request(self):
        _, provider_headers = signed_in("pro@example.com", UserRole.PROVIDER)
        self.assertEqual(self._post(**provider_headers).status_code, 403)
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_the_permissions_are_explicit(self):
        from accounts.permissions import IsClientAccount
        from matching.permissions import HasApiKey
        from rest_framework.permissions import IsAuthenticated

        from .views import ServiceRequestCreateView

        self.assertEqual(
            ServiceRequestCreateView.permission_classes, [HasApiKey, IsAuthenticated, IsClientAccount]
        )

    def test_a_missing_or_wrong_key_is_rejected_and_names_the_key(self):
        token = {"HTTP_AUTHORIZATION": self.signed_in_headers["HTTP_AUTHORIZATION"]}
        cases = {
            "no key": {},
            "wrong key": {"HTTP_X_API_KEY": "not-the-key"},
            "key with a trailing newline": {"HTTP_X_API_KEY": TEST_API_KEY + chr(10)},
            "key with a leading space": {"HTTP_X_API_KEY": " " + TEST_API_KEY},
            "empty key": {"HTTP_X_API_KEY": ""},
        }
        for name, headers in cases.items():
            # Not signed in: a 401. Signed in with a bad key: a 403. Either way
            # the message names the key, and nothing is created.
            for label, auth, expected in (("anonymous", {}, 401), ("signed in", token, 403)):
                with self.subTest(f"{name} ({label})"):
                    response = self._post(**auth, **headers)
                    self.assertEqual(response.status_code, expected)
                    self.assertEqual(response.json(), {"detail": "Missing or invalid API key."})
        self.assertEqual(ServiceRequest.objects.count(), 0)

    def test_a_non_ascii_key_is_rejected_not_a_server_error(self):
        response = self._post(HTTP_X_API_KEY="k\u00e9y")
        self.assertEqual(response.status_code, 401)

    def test_a_bad_key_is_rejected_the_same_way_on_the_endpoints_that_work(self):
        # The app's other calls go through the same gate, so a key problem
        # shows up everywhere, not only on submit.
        for path in ("/api/requests/mine/", "/api/catalog/categories/"):
            with self.subTest(path):
                response = self.client.get(path, HTTP_X_API_KEY="not-the-key")
                self.assertEqual(response.status_code, 401)
                self.assertEqual(response.json(), {"detail": "Missing or invalid API key."})


class WaitlistDemandAdminTests(TestCase):
    """The admin's "Waitlist demand" page: waitlisted requests only, with a
    demand-per-service summary."""

    URL = "/admin/provider_search/waitlistedrequest/"

    @classmethod
    def setUpTestData(cls):
        from django.contrib.auth import get_user_model

        cls.admin_user = get_user_model().objects.create_superuser("boss", "boss@example.com", "pw-for-tests-123")

    def setUp(self):
        self.client.force_login(self.admin_user)

        def make(category, device, status=ServiceRequest.STATUS_WAITLISTED, city="Edmonton"):
            return ServiceRequest.objects.create(
                device_id=device, category=category, city=city, phone="1", consent_given=True, status=status
            )

        # lawn-care: 3 requests from 2 devices; tree-services: 1; plumbing is launched ("new").
        make("lawn-care", "dev-a")
        make("lawn-care", "dev-a")
        make("lawn-care", "dev-b", city="Calgary")
        make("tree-services", "dev-c")
        make("plumbing", "dev-d", status=ServiceRequest.STATUS_NEW)

    def _demand(self, query=""):
        response = self.client.get(self.URL + query)
        self.assertEqual(response.status_code, 200)
        return response, {row["category"]: row for row in response.context_data["demand"]}

    def test_it_lists_only_waitlisted_requests_never_new_ones(self):
        response, demand = self._demand()
        self.assertEqual(set(demand), {"lawn-care", "tree-services"})
        self.assertEqual(response.context_data["cl"].result_count, 4)

    def test_it_counts_requests_and_distinct_devices_per_service_most_wanted_first(self):
        response, demand = self._demand()
        self.assertEqual([row["category"] for row in response.context_data["demand"]], ["lawn-care", "tree-services"])
        self.assertEqual((demand["lawn-care"]["requests"], demand["lawn-care"]["devices"]), (3, 2))
        self.assertEqual((demand["tree-services"]["requests"], demand["tree-services"]["devices"]), (1, 1))

    def test_it_names_the_service_and_says_whether_it_is_launched(self):
        _, demand = self._demand()
        self.assertEqual(demand["lawn-care"]["service_name"], Service.objects.get(slug="lawn-care").name)
        self.assertFalse(demand["lawn-care"]["launched"])
        # Once you open a service the table says so, and the requests stay listed.
        Service.objects.filter(slug="lawn-care").update(is_launched=True)
        _, demand = self._demand()
        self.assertTrue(demand["lawn-care"]["launched"])

    def test_the_summary_follows_the_filters(self):
        _, by_city = self._demand("?city=Calgary")
        self.assertEqual(set(by_city), {"lawn-care"})
        self.assertEqual(by_city["lawn-care"]["requests"], 1)
        _, by_service = self._demand("?category=tree-services")
        self.assertEqual(set(by_service), {"tree-services"})

    def test_the_page_renders_the_table_and_rows_show_service_names(self):
        response = self.client.get(self.URL)
        self.assertContains(response, "Demand by service")
        self.assertContains(response, Service.objects.get(slug="lawn-care").name)

    def test_nothing_can_be_added_there_and_it_needs_an_admin_login(self):
        self.assertEqual(self.client.get(self.URL + "add/").status_code, 403)
        self.client.logout()
        self.assertEqual(self.client.get(self.URL).status_code, 302)

    def test_service_is_launched_is_editable_straight_from_the_service_list(self):
        response = self.client.get("/admin/catalog/service/")
        self.assertEqual(response.status_code, 200)
        self.assertIn("is_launched", response.context_data["cl"].list_editable)
