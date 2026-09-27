from unittest.mock import patch

from django.test import SimpleTestCase, TestCase, override_settings

from .matching_engine import (
    CATEGORY_TAXONOMY, _keyword_categorize, keyword_suggestions, rank_keyword_categories,
)
from .views import CategorySuggestView

TEST_API_KEY = "test-key"


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
