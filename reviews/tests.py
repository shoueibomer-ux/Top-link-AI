from datetime import timedelta

from django.contrib import admin as django_admin
from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import RequestFactory, TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import UserProfile, UserRole
from leads.models import LeadOffer
from provider_search.models import ServiceRequest
from providers.models import ProviderProfile

from . import ratings
from .admin import ReviewReportAdmin
from .models import REVIEW_EDIT_WINDOW, Favorite, Review, ReviewReport

User = get_user_model()
KEY = "test-key"


def account(email, role, name):
    user = User.objects.create_user(username=email, email=email)
    UserProfile.objects.create(user=user, role=role, full_name=name)
    token = RefreshToken.for_user(user).access_token
    return user, {"HTTP_X_API_KEY": KEY, "HTTP_AUTHORIZATION": f"Bearer {token}"}


@override_settings(API_KEY=KEY)
class ReviewCase(TestCase):
    """A client with a completed job done by Ace Plumbing, plus a stranger client and a stranger provider."""

    def setUp(self):
        cache.delete_pattern("rl:*")
        self.client_user, self.client_h = account("client@example.com", UserRole.CUSTOMER, "Pat Client")
        self.provider_user, self.provider_h = account("ace@example.com", UserRole.PROVIDER, "Alex Owner")
        self.provider = self.make_provider(self.provider_user, "Ace Plumbing")
        self.request_obj = ServiceRequest.objects.create(
            user=self.client_user, category="plumbing", city="Edmonton", phone="+17805550199", consent_given=True
        )
        self.offer = self.make_offer(self.request_obj, self.provider, completed=True)
        self.stranger, self.stranger_h = account("nosy@example.com", UserRole.CUSTOMER, "Nosy Neighbour")
        self.other_user, self.other_h = account("other@example.com", UserRole.PROVIDER, "Other Owner")
        self.other_provider = self.make_provider(self.other_user, "Other Co")

    def make_provider(self, user, name, status=ProviderProfile.STATUS_APPROVED):
        return ProviderProfile.objects.create(
            user=user, business_name=name, phone=f"+1780555{abs(hash(name)) % 10000:04d}", email=user.email, status=status
        )

    def make_offer(self, request, provider, completed=False):
        offer = LeadOffer.objects.create(service_request=request, provider=provider)
        offer.status = LeadOffer.STATUS_ACCEPTED
        offer.sent_at = offer.responded_at = timezone.now()
        offer.hired = offer.job_completed = completed
        offer.save()
        return offer

    def review(self, rating=5, comment="Great work", offer=None, client=None, provider=None):
        offer = offer or self.offer
        return Review.objects.create(
            offer=offer, client=client or offer.service_request.user, provider=provider or offer.provider,
            rating=rating, comment=comment,
        )

    def send(self, method, name, headers, *args, body=None):
        url = reverse(name, args=args)
        if body is None and method in ("get", "delete"):
            return getattr(self.client, method)(url, **headers)
        return getattr(self.client, method)(url, body or {}, content_type="application/json", **headers)

    def age(self, review, days):
        Review.objects.filter(pk=review.pk).update(created_at=timezone.now() - timedelta(days=days))
        review.refresh_from_db()


class WritingReviewTests(ReviewCase):
    def test_client_reviews_a_completed_job(self):
        response = self.send("post", "offer-review", self.client_h, self.offer.id, body={"rating": 4, "comment": "  Fixed it fast  "})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["rating"], 4)
        self.assertEqual(response.json()["comment"], "Fixed it fast")
        self.assertEqual(response.json()["client_name"], "Pat C.")
        self.assertTrue(response.json()["can_edit"])
        review = Review.objects.get()
        self.assertEqual((review.provider, review.client, review.offer), (self.provider, self.client_user, self.offer))

    def test_comment_is_optional(self):
        response = self.send("post", "offer-review", self.client_h, self.offer.id, body={"rating": 3})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["comment"], "")

    def test_job_must_be_completed_first(self):
        open_offer = self.make_offer(ServiceRequest.objects.create(
            user=self.client_user, category="plumbing", city="Edmonton", phone="+17805550199", consent_given=True,
        ), self.other_provider)
        response = self.send("post", "offer-review", self.client_h, open_offer.id, body={"rating": 5})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(Review.objects.count(), 0)

    def test_only_one_review_per_job(self):
        self.send("post", "offer-review", self.client_h, self.offer.id, body={"rating": 5})
        again = self.send("post", "offer-review", self.client_h, self.offer.id, body={"rating": 1})
        self.assertEqual(again.status_code, 409)
        self.assertEqual(Review.objects.get().rating, 5)

    def test_rating_must_be_one_to_five(self):
        for bad in (0, 6, -1, "x", None, True, 4.5, [5]):
            response = self.send("post", "offer-review", self.client_h, self.offer.id, body={"rating": bad})
            self.assertEqual(response.status_code, 400, bad)
        self.assertEqual(Review.objects.count(), 0)

    def test_comment_length_is_capped(self):
        response = self.send("post", "offer-review", self.client_h, self.offer.id, body={"rating": 5, "comment": "x" * 1001})
        self.assertEqual(response.status_code, 400)

    def test_only_the_owning_client_can_review(self):
        for headers in (self.stranger_h, self.provider_h, self.other_h):
            response = self.send("post", "offer-review", headers, self.offer.id, body={"rating": 1})
            self.assertEqual(response.status_code, 404 if headers is self.stranger_h else 403)
        self.assertEqual(Review.objects.count(), 0)

    def test_needs_api_key_and_sign_in(self):
        url = reverse("offer-review", args=[self.offer.id])
        self.assertEqual(self.client.post(url, {"rating": 5}, content_type="application/json").status_code, 401)
        no_login = {"HTTP_X_API_KEY": KEY}
        self.assertEqual(self.client.post(url, {"rating": 5}, content_type="application/json", **no_login).status_code, 401)

    def test_get_my_review(self):
        self.assertEqual(self.send("get", "offer-review", self.client_h, self.offer.id).status_code, 404)
        self.review()
        response = self.send("get", "offer-review", self.client_h, self.offer.id)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.send("get", "offer-review", self.stranger_h, self.offer.id).status_code, 404)


class EditingReviewTests(ReviewCase):
    def test_client_can_edit_within_seven_days(self):
        review = self.review(rating=2, comment="Meh")
        self.age(review, 6)
        response = self.send("patch", "offer-review", self.client_h, self.offer.id, body={"rating": 5, "comment": "Actually great"})
        self.assertEqual(response.status_code, 200)
        review.refresh_from_db()
        self.assertEqual((review.rating, review.comment), (5, "Actually great"))
        self.assertTrue(response.json()["edited"])

    def test_editing_after_seven_days_is_refused(self):
        review = self.review(rating=2)
        self.age(review, 8)
        response = self.send("patch", "offer-review", self.client_h, self.offer.id, body={"rating": 5})
        self.assertEqual(response.status_code, 403)
        review.refresh_from_db()
        self.assertEqual(review.rating, 2)
        shown = self.send("get", "offer-review", self.client_h, self.offer.id).json()
        self.assertFalse(shown["can_edit"])

    def test_window_constant_is_seven_days(self):
        self.assertEqual(REVIEW_EDIT_WINDOW, timedelta(days=7))

    def test_unedited_review_is_not_marked_edited(self):
        self.review()
        shown = self.send("get", "offer-review", self.client_h, self.offer.id).json()
        self.assertFalse(shown["edited"])

    def test_someone_else_cannot_edit(self):
        review = self.review(rating=3)
        for headers in (self.stranger_h, self.provider_h):
            self.send("patch", "offer-review", headers, self.offer.id, body={"rating": 1})
        review.refresh_from_db()
        self.assertEqual(review.rating, 3)

    def test_hidden_review_cannot_be_edited(self):
        review = self.review(rating=3)
        Review.objects.filter(pk=review.pk).update(hidden=True)
        response = self.send("patch", "offer-review", self.client_h, self.offer.id, body={"rating": 5})
        self.assertEqual(response.status_code, 403)

    def test_invalid_edit_changes_nothing(self):
        review = self.review(rating=3, comment="ok")
        response = self.send("patch", "offer-review", self.client_h, self.offer.id, body={"rating": 9})
        self.assertEqual(response.status_code, 400)
        review.refresh_from_db()
        self.assertEqual((review.rating, review.comment, review.edited_at), (3, "ok", None))

    def test_clearing_the_comment_is_allowed(self):
        review = self.review(comment="old")
        self.send("patch", "offer-review", self.client_h, self.offer.id, body={"comment": ""})
        review.refresh_from_db()
        self.assertEqual(review.comment, "")


class RatingSummaryTests(ReviewCase):
    def second_review(self, rating, name="Sam Second"):
        client, _ = account(f"{name.split()[0].lower()}@example.com", UserRole.CUSTOMER, name)
        request = ServiceRequest.objects.create(user=client, category="plumbing", city="Edmonton", phone="+17805550177", consent_given=True)
        offer = self.make_offer(request, self.provider, completed=True)
        return self.review(rating=rating, offer=offer)

    def test_average_and_count(self):
        self.review(rating=5)
        self.second_review(4)
        summary = ratings.summary_for(self.provider.id)
        self.assertEqual(summary, {"rating_average": 4.5, "review_count": 2})

    def test_no_reviews(self):
        self.assertEqual(ratings.summary_for(self.provider.id), {"rating_average": None, "review_count": 0})

    def test_hidden_reviews_do_not_count(self):
        self.review(rating=5)
        bad = self.second_review(1)
        self.assertEqual(ratings.summary_for(self.provider.id)["rating_average"], 3.0)
        Review.objects.filter(pk=bad.pk).update(hidden=True)
        self.assertEqual(ratings.summary_for(self.provider.id), {"rating_average": 5.0, "review_count": 1})

    def test_summaries_for_several_providers_in_one_call(self):
        self.review(rating=3)
        result = ratings.summaries([self.provider.id, self.other_provider.id])
        self.assertEqual(result[self.provider.id]["review_count"], 1)
        self.assertEqual(result[self.other_provider.id]["review_count"], 0)

    def test_provider_profile_shows_own_rating(self):
        self.review(rating=4)
        profile = self.send("get", "provider-profile", self.provider_h).json()
        self.assertEqual((profile["rating_average"], profile["review_count"]), (4.0, 1))

    def test_matches_show_rating(self):
        self.review(rating=2)
        self.provider.categories.set([])
        from catalog.models import Service
        service = Service.objects.filter(slug="plumbing").first()
        if service is None:
            self.skipTest("no plumbing service in the catalog fixtures")
        self.provider.categories.add(service)
        self.provider.cities = ["Edmonton"]
        self.provider.save()
        response = self.client.get(reverse("provider-matches") + "?category=plumbing", HTTP_X_API_KEY=KEY)
        row = [r for r in response.json()["results"] if r["id"] == self.provider.id][0]
        self.assertEqual((row["rating_average"], row["review_count"]), (2.0, 1))


class HistoryTests(ReviewCase):
    def history_offer(self):
        response = self.client.get(reverse("service-request-list"), **self.client_h)
        self.assertEqual(response.status_code, 200)
        return response.json()["requests"][0]["accepted_offers"][0]

    def test_completed_job_without_review_can_be_reviewed(self):
        offer = self.history_offer()
        self.assertTrue(offer["can_review"])
        self.assertIsNone(offer["review"])
        self.assertEqual(offer["provider"]["review_count"], 0)

    def test_reviewed_job_shows_the_review_and_rating(self):
        self.review(rating=4, comment="Good")
        offer = self.history_offer()
        self.assertFalse(offer["can_review"])
        self.assertEqual(offer["review"]["rating"], 4)
        self.assertTrue(offer["review"]["mine"])
        self.assertEqual(offer["provider"]["rating_average"], 4.0)

    def test_job_not_yet_complete_cannot_be_reviewed(self):
        LeadOffer.objects.filter(pk=self.offer.pk).update(job_completed=False)
        self.assertFalse(self.history_offer()["can_review"])

    def test_history_query_count_does_not_grow_with_requests(self):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext

        self.review()
        with CaptureQueriesContext(connection) as one:
            self.client.get(reverse("service-request-list"), **self.client_h)
        for i in range(3):
            request = ServiceRequest.objects.create(
                user=self.client_user, category="plumbing", city="Edmonton", phone="+17805550199", consent_given=True
            )
            provider = self.make_provider(account(f"p{i}@example.com", UserRole.PROVIDER, "P P")[0], f"Co {i}")
            self.review(offer=self.make_offer(request, provider, completed=True), rating=3)
        with CaptureQueriesContext(connection) as many:
            self.client.get(reverse("service-request-list"), **self.client_h)
        self.assertLessEqual(len(many), len(one) + 1)


class PublicProviderPageTests(ReviewCase):
    def test_shows_reviews_with_shortened_client_name_and_no_contact_details(self):
        self.review(rating=5, comment="Great")
        response = self.send("get", "provider-reviews", self.stranger_h, self.provider.id)
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["reviews"][0]["client_name"], "Pat C.")
        self.assertEqual(body["provider"]["review_count"], 1)
        text = response.content.decode()
        for secret in ("client@example.com", "Pat Client", "+17805550199", "ace@example.com", self.provider.phone):
            self.assertNotIn(secret, text)

    def test_hidden_reviews_are_not_shown_or_counted(self):
        review = self.review(rating=1, comment="Rude")
        Review.objects.filter(pk=review.pk).update(hidden=True)
        body = self.send("get", "provider-reviews", self.stranger_h, self.provider.id).json()
        self.assertEqual(body["reviews"], [])
        self.assertEqual(body["provider"]["review_count"], 0)

    def test_unapproved_provider_has_no_page(self):
        ProviderProfile.objects.filter(pk=self.provider.pk).update(status=ProviderProfile.STATUS_PENDING)
        self.assertEqual(self.send("get", "provider-reviews", self.stranger_h, self.provider.id).status_code, 404)

    def test_requires_sign_in(self):
        url = reverse("provider-reviews", args=[self.provider.id])
        self.assertEqual(self.client.get(url, HTTP_X_API_KEY=KEY).status_code, 401)

    def test_is_favorite_flag(self):
        self.assertFalse(self.send("get", "provider-reviews", self.client_h, self.provider.id).json()["is_favorite"])
        Favorite.objects.create(user=self.client_user, provider=self.provider)
        self.assertTrue(self.send("get", "provider-reviews", self.client_h, self.provider.id).json()["is_favorite"])
        self.assertFalse(self.send("get", "provider-reviews", self.stranger_h, self.provider.id).json()["is_favorite"])

    def test_mine_flag_only_for_the_author(self):
        self.review()
        mine = self.send("get", "provider-reviews", self.client_h, self.provider.id).json()["reviews"][0]
        theirs = self.send("get", "provider-reviews", self.stranger_h, self.provider.id).json()["reviews"][0]
        self.assertTrue(mine["mine"])
        self.assertFalse(theirs["mine"])
        self.assertNotIn("can_edit", theirs)


class ReplyTests(ReviewCase):
    def test_provider_replies_once(self):
        review = self.review()
        response = self.send("post", "review-reply", self.provider_h, review.id, body={"text": "  Thanks Pat!  "})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["reply"]["text"], "Thanks Pat!")
        again = self.send("post", "review-reply", self.provider_h, review.id, body={"text": "And again"})
        self.assertEqual(again.status_code, 409)
        review.refresh_from_db()
        self.assertEqual(review.reply, "Thanks Pat!")

    def test_reply_is_public(self):
        review = self.review()
        self.send("post", "review-reply", self.provider_h, review.id, body={"text": "Thanks!"})
        body = self.send("get", "provider-reviews", self.stranger_h, self.provider.id).json()
        self.assertEqual(body["reviews"][0]["reply"]["text"], "Thanks!")

    def test_only_the_reviewed_provider_can_reply(self):
        review = self.review()
        for headers, expected in ((self.other_h, 404), (self.client_h, 403), (self.stranger_h, 403)):
            self.assertEqual(self.send("post", "review-reply", headers, review.id, body={"text": "hi"}).status_code, expected)
        review.refresh_from_db()
        self.assertEqual(review.reply, "")

    def test_reply_cannot_be_empty_or_too_long(self):
        review = self.review()
        for text in ("", "   ", None):
            self.assertEqual(self.send("post", "review-reply", self.provider_h, review.id, body={"text": text}).status_code, 400)
        self.assertEqual(self.send("post", "review-reply", self.provider_h, review.id, body={"text": "x" * 1001}).status_code, 400)

    def test_cannot_reply_to_a_hidden_review(self):
        review = self.review()
        Review.objects.filter(pk=review.pk).update(hidden=True)
        self.assertEqual(self.send("post", "review-reply", self.provider_h, review.id, body={"text": "hi"}).status_code, 404)

    def test_provider_sees_their_own_reviews(self):
        review = self.review(rating=3)
        body = self.send("get", "my-provider-reviews", self.provider_h).json()
        self.assertEqual(body["summary"], {"rating_average": 3.0, "review_count": 1})
        self.assertEqual(body["reviews"][0]["id"], review.id)
        self.assertEqual(self.send("get", "my-provider-reviews", self.other_h).json()["reviews"], [])
        self.assertEqual(self.send("get", "my-provider-reviews", self.client_h).status_code, 403)


class ReportTests(ReviewCase):
    def test_a_signed_in_person_can_report_a_review(self):
        review = self.review()
        response = self.send("post", "review-report", self.stranger_h, review.id, body={"reason": "spam", "details": "Looks fake"})
        self.assertEqual(response.status_code, 201)
        report = ReviewReport.objects.get()
        self.assertEqual((report.review, report.reporter, report.status), (review, self.stranger, ReviewReport.STATUS_OPEN))
        review.refresh_from_db()
        self.assertFalse(review.hidden)  # stays up until staff act

    def test_the_reviewed_provider_can_report(self):
        review = self.review()
        self.assertEqual(self.send("post", "review-report", self.provider_h, review.id, body={"reason": "fake"}).status_code, 201)

    def test_reporting_twice_makes_one_report(self):
        review = self.review()
        for _ in range(2):
            self.send("post", "review-report", self.stranger_h, review.id, body={"reason": "spam"})
        self.assertEqual(ReviewReport.objects.count(), 1)

    def test_cannot_report_your_own_review(self):
        review = self.review()
        self.assertEqual(self.send("post", "review-report", self.client_h, review.id, body={"reason": "spam"}).status_code, 400)

    def test_bad_reason_is_refused(self):
        review = self.review()
        for reason in (None, "", "because", 5):
            self.assertEqual(self.send("post", "review-report", self.stranger_h, review.id, body={"reason": reason}).status_code, 400)

    def test_unknown_review_is_404(self):
        self.assertEqual(self.send("post", "review-report", self.stranger_h, 9999, body={"reason": "spam"}).status_code, 404)


class AdminModerationTests(ReviewCase):
    def setUp(self):
        super().setUp()
        self.staff = User.objects.create_superuser(username="boss", email="boss@example.com", password="x")

    def admin_request(self):
        request = RequestFactory().post("/admin/")
        request.user = self.staff
        request.session = {}
        request._messages = type("M", (), {"add": lambda *a, **k: None})()
        return request

    def test_hiding_via_a_report_removes_the_review_and_its_rating(self):
        review = self.review(rating=1, comment="Rude")
        self.send("post", "review-report", self.stranger_h, review.id, body={"reason": "abusive"})
        report_admin = ReviewReportAdmin(ReviewReport, django_admin.site)
        report_admin.hide_review(self.admin_request(), ReviewReport.objects.all())
        review.refresh_from_db()
        self.assertTrue(review.hidden)
        self.assertIn("Reported", review.hidden_reason)
        self.assertEqual(ReviewReport.objects.get().status, ReviewReport.STATUS_ACTIONED)
        self.assertEqual(ratings.summary_for(self.provider.id)["review_count"], 0)
        self.assertEqual(self.send("get", "provider-reviews", self.stranger_h, self.provider.id).json()["reviews"], [])

    def test_dismissing_keeps_the_review(self):
        review = self.review()
        self.send("post", "review-report", self.stranger_h, review.id, body={"reason": "spam"})
        ReviewReportAdmin(ReviewReport, django_admin.site).dismiss(self.admin_request(), ReviewReport.objects.all())
        review.refresh_from_db()
        self.assertFalse(review.hidden)
        self.assertEqual(ReviewReport.objects.get().status, ReviewReport.STATUS_DISMISSED)

    def test_author_still_sees_their_hidden_review_marked_hidden(self):
        review = self.review()
        Review.objects.filter(pk=review.pk).update(hidden=True)
        shown = self.send("get", "offer-review", self.client_h, self.offer.id).json()
        self.assertTrue(shown["hidden"])
        self.assertFalse(shown["can_edit"])

    def test_admin_pages_load(self):
        review = self.review()
        self.send("post", "review-report", self.stranger_h, review.id, body={"reason": "spam"})
        self.client.force_login(self.staff)
        for name in ("reviews_review_changelist", "reviews_reviewreport_changelist", "reviews_favorite_changelist"):
            self.assertEqual(self.client.get(reverse(f"admin:{name}")).status_code, 200, name)
        self.assertEqual(self.client.get(reverse("admin:reviews_review_change", args=[review.id])).status_code, 200)
        self.assertEqual(
            self.client.get(reverse("admin:reviews_reviewreport_change", args=[ReviewReport.objects.get().id])).status_code, 200
        )


class FavoriteTests(ReviewCase):
    def test_save_list_and_remove(self):
        self.review(rating=5)
        self.assertEqual(self.send("get", "favorites", self.client_h).json()["favorites"], [])
        self.assertEqual(self.send("put", "favorite", self.client_h, self.provider.id).json(), {"is_favorite": True})
        listed = self.send("get", "favorites", self.client_h).json()["favorites"]
        self.assertEqual([f["business_name"] for f in listed], ["Ace Plumbing"])
        self.assertEqual((listed[0]["rating_average"], listed[0]["review_count"]), (5.0, 1))
        self.assertEqual(self.send("delete", "favorite", self.client_h, self.provider.id).json(), {"is_favorite": False})
        self.assertEqual(self.send("get", "favorites", self.client_h).json()["favorites"], [])

    def test_saving_twice_is_harmless(self):
        for _ in range(2):
            self.assertEqual(self.send("put", "favorite", self.client_h, self.provider.id).status_code, 200)
        self.assertEqual(Favorite.objects.count(), 1)
        for _ in range(2):
            self.assertEqual(self.send("delete", "favorite", self.client_h, self.provider.id).status_code, 200)

    def test_favorites_are_private_to_each_client(self):
        self.send("put", "favorite", self.client_h, self.provider.id)
        self.assertEqual(self.send("get", "favorites", self.stranger_h).json()["favorites"], [])
        self.send("delete", "favorite", self.stranger_h, self.provider.id)  # can't remove someone else's
        self.assertEqual(Favorite.objects.count(), 1)

    def test_providers_cannot_use_favorites(self):
        self.assertEqual(self.send("get", "favorites", self.provider_h).status_code, 403)
        self.assertEqual(self.send("put", "favorite", self.provider_h, self.other_provider.id).status_code, 403)

    def test_cannot_save_an_unapproved_provider(self):
        pending = self.make_provider(account("new@example.com", UserRole.PROVIDER, "New Owner")[0], "New Co", ProviderProfile.STATUS_PENDING)
        self.assertEqual(self.send("put", "favorite", self.client_h, pending.id).status_code, 404)
        self.assertEqual(self.send("put", "favorite", self.client_h, 9999).status_code, 404)

    def test_provider_that_loses_approval_drops_out_of_the_list(self):
        self.send("put", "favorite", self.client_h, self.provider.id)
        ProviderProfile.objects.filter(pk=self.provider.pk).update(status=ProviderProfile.STATUS_REJECTED)
        self.assertEqual(self.send("get", "favorites", self.client_h).json()["favorites"], [])

    def test_needs_sign_in(self):
        self.assertEqual(self.client.get(reverse("favorites"), HTTP_X_API_KEY=KEY).status_code, 401)
        self.assertEqual(self.client.get(reverse("favorites")).status_code, 401)
