from unittest.mock import patch

from django.test import TestCase, override_settings
from django.utils import timezone

from matching.models import Subscription
from .models import ProviderMatch, ServiceRequest
from .serializers import mask_phone

TEST_API_KEY = "test-key"


def fake_places(category: str, name_prefix: str) -> list[dict]:
    return [
        {
            "place_id": f"{category}-place-1",
            "name": f"{name_prefix} Pros",
            "address": "123 Main St NW, Edmonton, AB T5T 2V9, Canada",
            "phone": "+1 780-904-1234",
            "website": "https://example.com",
            "rating": 4.8,
            "rating_count": 120,
            "maps_url": "https://maps.example.com/1",
        },
        {
            "place_id": f"{category}-place-2",
            "name": f"{name_prefix} Experts",
            "address": "456 Side Ave, Edmonton, AB T5T 2V9, Canada",
            "phone": "+1 780-555-9876",
            "website": "https://example2.com",
            "rating": 4.5,
            "rating_count": 42,
            "maps_url": "https://maps.example.com/2",
        },
    ]


@override_settings(API_KEY=TEST_API_KEY, GOOGLE_PLACES_API_KEY="unused-in-tests")
class ProviderGatingTests(TestCase):
    """Covers every category the same way — parametrized over 'plumbing' and
    'towing-services' — per the requirement that the fix isn't specific to
    whichever category happened to be shown while testing."""

    def setUp(self):
        self.headers = {"HTTP_X_API_KEY": TEST_API_KEY}

    def _search(self, category, city="Edmonton", device_id="device-a"):
        with patch("provider_search.views.search_providers") as mocked:
            mocked.return_value = fake_places(category, category.title())
            return self.client.get(
                "/api/providers/search/",
                {"category": category, "city": city, "device_id": device_id},
                **self.headers,
            )

    def _unlock(self, category, place_id, device_id="device-a", city="Edmonton", paid=None):
        with patch("provider_search.views.search_providers") as mocked:
            mocked.return_value = fake_places(category, category.title())
            body = {"device_id": device_id, "place_id": place_id, "category": category, "city": city}
            if paid is not None:
                body["paid"] = paid
            return self.client.post("/api/providers/unlock/", body, content_type="application/json", **self.headers)

    def _subscribe(self, device_id="device-a"):
        Subscription.objects.create(
            device_id=device_id,
            status="active",
            start_date=timezone.now(),
            expiry_date=timezone.now() + timezone.timedelta(days=30),
        )

    # ---- mask_phone() itself ----

    def test_mask_phone_keeps_area_code_and_exchange_masks_last_four(self):
        self.assertEqual(mask_phone("+1 780-904-1234"), "+1 780-904-XXXX")
        self.assertEqual(mask_phone(""), "")

    # ---- Issue 1: search never leaks full contact info, for any category, subscribed or not ----

    def test_search_masks_phone_and_omits_address_for_unsubscribed_device(self):
        for category in ("plumbing", "towing-services"):
            with self.subTest(category=category):
                response = self._search(category, device_id="unsub-device")
                self.assertEqual(response.status_code, 200)
                providers = response.json()["providers"]
                self.assertEqual(len(providers), 2)
                for p in providers:
                    self.assertFalse(p["is_unlocked"])
                    self.assertNotIn("1234", p["phone"])
                    self.assertTrue(p["phone"].endswith("XXXX"))
                    self.assertIsNone(p["address"])
                    self.assertIsNone(p["website"])
                    self.assertIsNone(p["maps_url"])
                    self.assertEqual(p["city"], "Edmonton")  # free descriptive info stays

    def test_search_ALSO_masks_for_a_subscribed_device_until_explicit_unlock(self):
        """The core Issue 1/2 fix: an active subscription must not make
        search itself return full contact info or create request rows —
        only an explicit unlock does that."""
        self._subscribe("sub-device")
        response = self._search("plumbing", device_id="sub-device")
        body = response.json()
        self.assertTrue(body["is_subscribed"])
        for p in body["providers"]:
            self.assertFalse(p["is_unlocked"])
            self.assertIsNone(p["address"])
            self.assertTrue(p["phone"].endswith("XXXX"))
        self.assertEqual(ProviderMatch.objects.count(), 0)

    def test_free_preview_keeps_rating_availability_and_response_time_visible(self):
        response = self._search("cleaning-services", device_id="anon-device")
        provider = response.json()["providers"][0]
        self.assertEqual(provider["rating"], 4.8)
        self.assertEqual(provider["rating_count"], 120)
        self.assertIn("is_available_now", provider)
        self.assertIsNotNone(provider["estimated_response_minutes"])

    # ---- Issue 2: search never creates a ProviderMatch / "Your requests" row ----

    def test_search_creates_no_provider_match_rows_at_all(self):
        for category in ("plumbing", "towing-services"):
            self._search(category, device_id="device-b")
        self.assertEqual(ProviderMatch.objects.count(), 0)

    def test_search_still_creates_a_service_request_and_marks_it_found(self):
        response = self._search("plumbing", device_id="device-c")
        sr_id = response.json()["service_request_id"]
        service_request = ServiceRequest.objects.get(id=sr_id)
        self.assertEqual(service_request.status, ProviderMatch.STATUS_FOUND)

    # ---- Unlock gate ----

    def test_unlock_without_subscription_or_payment_is_rejected_and_creates_nothing(self):
        response = self._unlock("plumbing", "plumbing-place-1", device_id="broke-device")
        self.assertEqual(response.status_code, 402)
        self.assertEqual(ProviderMatch.objects.count(), 0)

    def test_paid_unlock_reveals_full_details_and_creates_a_requested_row(self):
        for category in ("plumbing", "towing-services"):
            with self.subTest(category=category):
                place_id = f"{category}-place-1"
                response = self._unlock(category, place_id, device_id=f"paid-{category}", paid=True)
                self.assertEqual(response.status_code, 200)
                body = response.json()["provider"]
                self.assertTrue(body["is_unlocked"])
                self.assertEqual(body["phone"], "+1 780-904-1234")
                self.assertIn("123 Main St", body["address"])

                match = ProviderMatch.objects.get(device_id=f"paid-{category}", place_id=place_id)
                self.assertEqual(match.status, ProviderMatch.STATUS_REQUESTED)
                self.assertEqual(match.unlock_method, ProviderMatch.UNLOCK_METHOD_PAID)

    def test_subscribed_unlock_is_free_and_recorded_as_subscription_method(self):
        self._subscribe("sub-unlocker")
        response = self._unlock("plumbing", "plumbing-place-1", device_id="sub-unlocker")
        self.assertEqual(response.status_code, 200)
        match = ProviderMatch.objects.get(device_id="sub-unlocker", place_id="plumbing-place-1")
        self.assertEqual(match.unlock_method, ProviderMatch.UNLOCK_METHOD_SUBSCRIPTION)
        self.assertEqual(match.status, ProviderMatch.STATUS_REQUESTED)

    def test_unlocking_one_provider_does_not_unlock_others_in_the_same_search(self):
        self._unlock("plumbing", "plumbing-place-1", device_id="picky-device", paid=True)
        response = self._search("plumbing", device_id="picky-device")
        providers = {p["place_id"]: p for p in response.json()["providers"]}
        self.assertTrue(providers["plumbing-place-1"]["is_unlocked"])
        self.assertFalse(providers["plumbing-place-2"]["is_unlocked"])
        self.assertIsNone(providers["plumbing-place-2"]["address"])

    def test_reunlocking_refreshes_contact_details_but_never_resets_progressed_status(self):
        self._unlock("plumbing", "plumbing-place-1", device_id="repeat-device", paid=True)
        match = ProviderMatch.objects.get(device_id="repeat-device", place_id="plumbing-place-1")
        match.status = ProviderMatch.STATUS_COMPLETED
        match.save(update_fields=["status"])

        response = self._unlock("plumbing", "plumbing-place-1", device_id="repeat-device", paid=True)
        self.assertEqual(response.status_code, 200)
        match.refresh_from_db()
        self.assertEqual(match.status, ProviderMatch.STATUS_COMPLETED)
        self.assertEqual(ProviderMatch.objects.filter(device_id="repeat-device").count(), 1)

    def test_unlock_requires_a_known_category_and_city(self):
        response = self._unlock("not-a-real-category", "x", device_id="d", paid=True)
        self.assertEqual(response.status_code, 400)

    # ---- "Your requests" only grows from real unlocks, and starts at "requested" ----

    def test_your_requests_list_only_contains_explicitly_unlocked_providers(self):
        device_id = "history-device"
        self._search("plumbing", device_id=device_id)
        self._search("towing-services", device_id=device_id)
        self.assertEqual(
            self.client.get(f"/api/provider-matches/?device_id={device_id}", **self.headers).json()["matches"], []
        )

        self._unlock("plumbing", "plumbing-place-1", device_id=device_id, paid=True)
        matches = self.client.get(f"/api/provider-matches/?device_id={device_id}", **self.headers).json()["matches"]
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0]["status"], "requested")
        self.assertNotEqual(matches[0]["status"], "matched")
