from django.core.cache import cache
from unittest.mock import patch

from django.test import SimpleTestCase, TestCase, override_settings
from django.utils import timezone

from notifications.models import Notification
from .access import consume_credit, credits_available, has_access
from .matching_engine import (
    CATEGORY_TAXONOMY, _keyword_categorize, keyword_suggestions, rank_keyword_categories,
)
from .models import Subscription, UnlockCredit
from .views import CategorySuggestView

TEST_API_KEY = "test-key"


@override_settings(API_KEY=TEST_API_KEY)
class UnlockCreditActivateTests(TestCase):
    """POST /api/unlock-credits/activate/ — records the paywall's "$4.99
    one-time" purchase as one pending, single-use unlock credit."""

    def setUp(self):
        self.headers = {"HTTP_X_API_KEY": TEST_API_KEY}
        # django-ratelimit's counters live in the real Redis-backed cache,
        # which TestCase doesn't reset — clear only its own "rl:" keys.
        cache.delete_pattern("rl:*")

    def tearDown(self):
        cache.delete_pattern("rl:*")

    def _activate(self, **body):
        return self.client.post(
            "/api/unlock-credits/activate/", body, content_type="application/json", **self.headers
        )

    def test_activating_grants_one_pending_credit_and_notifies_the_device(self):
        response = self._activate(device_id="dev-1", transaction_id="txn-1")

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json(), {"unlock_credits": 1, "has_access": True, "created": True})
        credit = UnlockCredit.objects.get(device_id="dev-1")
        self.assertIsNone(credit.consumed_at)
        self.assertTrue(Notification.objects.filter(device_id="dev-1", title="Your one-time unlock is ready").exists())

    def test_replaying_the_same_purchase_does_not_mint_a_second_credit(self):
        self._activate(device_id="dev-1", transaction_id="txn-1")
        replay = self._activate(device_id="dev-1", transaction_id="txn-1")

        self.assertEqual(replay.status_code, 200)
        self.assertFalse(replay.json()["created"])
        self.assertEqual(UnlockCredit.objects.filter(device_id="dev-1").count(), 1)
        self.assertEqual(Notification.objects.filter(device_id="dev-1").count(), 1)  # no repeat notification

    def test_a_purchase_already_redeemed_by_another_device_is_rejected(self):
        self._activate(device_id="dev-1", transaction_id="txn-1")
        stolen = self._activate(device_id="dev-2", transaction_id="txn-1")

        self.assertEqual(stolen.status_code, 409)
        self.assertEqual(credits_available("dev-2"), 0)

    def test_two_separate_purchases_grant_two_credits(self):
        self._activate(device_id="dev-1", transaction_id="txn-1")
        self._activate(device_id="dev-1", transaction_id="txn-2")
        self.assertEqual(credits_available("dev-1"), 2)

    def test_a_purchase_with_no_transaction_id_is_accepted_for_the_dev_fallback_path(self):
        self.assertEqual(self._activate(device_id="dev-1").status_code, 201)
        self.assertEqual(self._activate(device_id="dev-1").status_code, 201)
        self.assertEqual(credits_available("dev-1"), 2)

    def test_device_id_is_required_and_bounded(self):
        self.assertEqual(self._activate(transaction_id="txn-1").status_code, 400)
        self.assertEqual(self._activate(device_id="", transaction_id="txn-1").status_code, 400)
        self.assertEqual(self._activate(device_id="x" * 65).status_code, 400)
        self.assertEqual(self._activate(device_id="dev-1", transaction_id="t" * 256).status_code, 400)
        self.assertEqual(UnlockCredit.objects.count(), 0)

    def test_activation_is_rate_limited_per_source(self):
        for i in range(10):
            self.assertEqual(self._activate(device_id="dev-1", transaction_id=f"txn-{i}").status_code, 201)
        eleventh = self._activate(device_id="dev-1", transaction_id="txn-10")

        self.assertEqual(eleventh.status_code, 429)
        self.assertEqual(credits_available("dev-1"), 10)  # the blocked call minted nothing

    def test_requires_the_api_key(self):
        response = self.client.post(
            "/api/unlock-credits/activate/", {"device_id": "dev-1"}, content_type="application/json"
        )
        # 401 rather than 403: the JWT authenticator advertises a
        # WWW-Authenticate header, so DRF reports "not authenticated".
        self.assertEqual(response.status_code, 401)
        self.assertEqual(UnlockCredit.objects.count(), 0)


@override_settings(API_KEY=TEST_API_KEY)
class AccessRulesTests(TestCase):
    """What the app's up-front gate (subscription.AppEntryPoint) reads from
    GET /api/subscription/: `has_access` and `unlock_credits`."""

    def setUp(self):
        self.headers = {"HTTP_X_API_KEY": TEST_API_KEY}

    def _status(self, device_id):
        return self.client.get("/api/subscription/", {"device_id": device_id}, **self.headers).json()

    def test_a_brand_new_device_has_no_access_and_no_credits(self):
        body = self._status("fresh")
        self.assertEqual(body["status"], "inactive")
        self.assertEqual(body["unlock_credits"], 0)
        self.assertFalse(body["has_access"])

    def test_an_unspent_credit_grants_access(self):
        UnlockCredit.objects.create(device_id="buyer")
        body = self._status("buyer")
        self.assertEqual(body["unlock_credits"], 1)
        self.assertTrue(body["has_access"])
        self.assertEqual(body["status"], "inactive")  # still not a subscriber

    def test_access_survives_spending_the_credit_so_the_unlocked_contact_stays_viewable(self):
        UnlockCredit.objects.create(device_id="buyer")
        self.assertTrue(consume_credit("buyer", "some-place"))

        body = self._status("buyer")
        self.assertEqual(body["unlock_credits"], 0)
        self.assertTrue(body["has_access"])

    def test_an_active_subscription_grants_access_without_credits(self):
        Subscription.objects.create(
            device_id="sub",
            status="active",
            start_date=timezone.now(),
            expiry_date=timezone.now() + timezone.timedelta(days=30),
        )
        body = self._status("sub")
        self.assertEqual(body["status"], "active")
        self.assertEqual(body["unlock_credits"], 0)
        self.assertTrue(body["has_access"])

    def test_an_expired_subscription_alone_does_not_grant_access(self):
        Subscription.objects.create(
            device_id="lapsed",
            status="active",
            start_date=timezone.now() - timezone.timedelta(days=60),
            expiry_date=timezone.now() - timezone.timedelta(days=30),
        )
        self.assertFalse(self._status("lapsed")["has_access"])

    def test_credits_are_spent_oldest_first_and_only_once_each(self):
        first = UnlockCredit.objects.create(device_id="buyer")
        second = UnlockCredit.objects.create(device_id="buyer")

        self.assertTrue(consume_credit("buyer", "place-a"))
        first.refresh_from_db()
        second.refresh_from_db()
        self.assertEqual(first.consumed_place_id, "place-a")
        self.assertIsNone(second.consumed_at)

        self.assertTrue(consume_credit("buyer", "place-b"))
        self.assertFalse(consume_credit("buyer", "place-c"))  # none left
        self.assertTrue(has_access("buyer"))


class KeywordClassifierTests(SimpleTestCase):
    """The keyword classifier that Ask AI falls back to, and that the category
    search bar uses on its own (see CategorySuggestView)."""

    def test_free_text_resolves_to_the_right_category(self):
        self.assertEqual(rank_keyword_categories("leaking pipe")[0], "plumbing")
        self.assertEqual(rank_keyword_categories("my furnace stopped working")[0], "hvac")
        self.assertEqual(rank_keyword_categories("need someone to mow my lawn")[0], "lawn-care")

    def test_no_keyword_means_no_category(self):
        self.assertEqual(rank_keyword_categories("zzzz qqqq"), [])
        self.assertEqual(rank_keyword_categories(""), [])

    def test_matching_ignores_case(self):
        self.assertEqual(rank_keyword_categories("LEAKING PIPE")[0], "plumbing")

    def test_more_keyword_hits_rank_first(self):
        # "roof leak" is a plumbing keyword hit ("leak") AND two roofing ones.
        ranked = rank_keyword_categories("roof leak")
        self.assertEqual(ranked[0], "roofing")
        self.assertIn("plumbing", ranked)

    def test_ranking_is_deterministic(self):
        first = rank_keyword_categories("fix a leaking pipe in the kitchen")
        for _ in range(20):
            self.assertEqual(rank_keyword_categories("fix a leaking pipe in the kitchen"), first)

    def test_the_ai_fallback_still_gets_the_same_set(self):
        # _keyword_categorize is what ai_categorize() falls back to; ranking
        # must not change which categories it finds.
        text = "roof leak"
        self.assertEqual(_keyword_categorize(text), set(rank_keyword_categories(text)))

    def test_every_taxonomy_keyword_finds_its_own_category(self):
        for category, keywords in CATEGORY_TAXONOMY.items():
            for keyword in keywords:
                self.assertIn(category, rank_keyword_categories(keyword), f"{keyword!r} -> {category}")


class KeywordSuggestionTests(SimpleTestCase):
    def test_a_prefix_suggests_the_keyword_and_its_category(self):
        self.assertIn({"keyword": "faucet", "category": "plumbing"}, keyword_suggestions("fauc"))

    def test_the_last_word_typed_can_complete_a_keyword_word(self):
        self.assertIn({"keyword": "pipe", "category": "plumbing"}, keyword_suggestions("leaking pi"))

    def test_whole_query_prefix_matches_come_before_last_word_matches(self):
        # "water heater" starts with "water"; "wall finish"/others match on
        # a later word only.
        results = keyword_suggestions("heat")
        self.assertEqual(results[0]["keyword"], "heating")

    def test_too_short_or_blank_queries_suggest_nothing(self):
        self.assertEqual(keyword_suggestions(""), [])
        self.assertEqual(keyword_suggestions("p"), [])
        self.assertEqual(keyword_suggestions("   "), [])

    def test_results_are_capped(self):
        self.assertLessEqual(len(keyword_suggestions("re", limit=3)), 3)

    def test_trailing_space_keywords_are_stripped(self):
        # "ac " is stored with a trailing space to avoid matching inside words.
        self.assertTrue(all(s["keyword"] == s["keyword"].strip() for s in keyword_suggestions("ac")))


@override_settings(API_KEY=TEST_API_KEY)
class CategorySuggestViewTests(TestCase):
    """GET /api/categories/suggest/ — backs the category search bar."""

    def setUp(self):
        self.headers = {"HTTP_X_API_KEY": TEST_API_KEY}

    def _get(self, q, **extra):
        return self.client.get("/api/categories/suggest/", {"q": q}, **{**self.headers, **extra})

    def test_free_text_resolves_to_a_category(self):
        body = self._get("leaking pipe").json()
        self.assertEqual(body["categories"][0], "plumbing")
        self.assertEqual(body["query"], "leaking pipe")

    def test_a_partial_word_returns_keyword_suggestions(self):
        body = self._get("fauc").json()
        self.assertIn({"keyword": "faucet", "category": "plumbing"}, body["keywords"])

    def test_unrecognised_text_returns_empty_lists_not_an_error(self):
        response = self._get("zzzz qqqq")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["categories"], [])
        self.assertEqual(response.json()["keywords"], [])

    def test_missing_or_blank_query_is_empty_not_an_error(self):
        for path in ("/api/categories/suggest/", "/api/categories/suggest/?q="):
            response = self.client.get(path, **self.headers)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json()["categories"], [])

    def test_it_requires_the_api_key(self):
        response = self.client.get("/api/categories/suggest/", {"q": "pipe"})
        self.assertEqual(response.status_code, 401)

    def test_an_oversized_query_is_truncated_not_rejected(self):
        body = self._get("pipe " * 500).json()
        self.assertLessEqual(len(body["query"]), CategorySuggestView.MAX_QUERY_LENGTH)

    def test_it_never_calls_the_claude_api(self):
        with patch("matching.matching_engine._ai_categorize_llm") as llm:
            self._get("leaking pipe")
        llm.assert_not_called()
