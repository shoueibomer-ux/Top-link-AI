from datetime import timedelta
from io import StringIO
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.management import CommandError, call_command
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework_simplejwt.tokens import RefreshToken

from catalog.models import Service
from leads import jobs
from leads.models import LeadOffer
from messaging import photo_queue
from messaging.models import (
    ChatTermsAcceptance,
    Conversation,
    ConversationRead,
    DeviceToken,
    Message,
    MessageReport,
    PhotoDeletion,
    UserBlock,
)
from notifications.models import Notification
from provider_search.models import ServiceRequest
from providers.google_auth import GoogleUser
from providers.google_signin import user_for_google
from providers.models import GoogleIdentity, ProviderProfile
from reviews.models import Favorite, Review, ReviewReport

from .deletion import DELETED_EMAIL_DOMAIN, DELETED_PROVIDER_NAME, AccountNotDeletable, delete_account
from .models import AccountDeletion, UserProfile, UserRole

User = get_user_model()
KEY = "test-key"
R2 = dict(R2_ACCOUNT_ID="acct", R2_ACCESS_KEY_ID="AKIAFAKE", R2_SECRET_ACCESS_KEY="shh", R2_BUCKET="bucket")


def account(email, role, name):
    user = User.objects.create_user(username=email, email=email)
    UserProfile.objects.create(user=user, role=role, full_name=name)
    return user


def headers_for(user):
    token = RefreshToken.for_user(user).access_token
    return {"HTTP_X_API_KEY": KEY, "HTTP_AUTHORIZATION": f"Bearer {token}"}


@override_settings(API_KEY=KEY)
class DeletionCase(TestCase):
    """Pat (a client) and Ace (a provider) have a job, a chat with a photo, a review and a reply; Sam is a bystander."""

    def setUp(self):
        cache.clear()
        self.pat = account("pat@example.com", UserRole.CUSTOMER, "Pat Client")
        self.ace_user = account("ace@example.com", UserRole.PROVIDER, "Alex Owner")
        self.sam = account("sam@example.com", UserRole.CUSTOMER, "Sam Bystander")
        self.ace = ProviderProfile.objects.create(
            user=self.ace_user, business_name="Ace Plumbing", phone="+17805550101", email="office@ace.example",
            cities=["Edmonton"], waitlist_cities=["Calgary"], bio="Family run since 1998", notes="Called twice",
            review_note="Welcome", status=ProviderProfile.STATUS_APPROVED, sms_consent_at=timezone.now(),
        )
        self.ace.categories.set(Service.objects.filter(slug="plumbing"))

        self.request = ServiceRequest.objects.create(
            user=self.pat, category="plumbing", city="Edmonton", phone="+17805550199", consent_given=True,
            urgency="today", problem_description="Leaking kitchen sink", location="T5J 0N3", device_id="device-pat",
            required_skills=["pipefitting"], required_equipment=["wrench"], required_qualifications=["licence"],
        )
        self.offer = self.make_offer(self.request, self.ace, LeadOffer.STATUS_ACCEPTED, completed=True)
        self.review = Review.objects.create(
            offer=self.offer, client=self.pat, provider=self.ace, rating=5, comment="Great work",
            reply="Thanks Pat!", reply_at=timezone.now(),
        )
        self.conversation = Conversation.objects.create(offer=self.offer)
        Message.objects.create(conversation=self.conversation, sender=self.pat, body="Hi, it's Pat at 12 Elm St")
        Message.objects.create(conversation=self.conversation, sender=self.ace_user, body="On my way")
        Message.objects.create(conversation=self.conversation, sender=self.pat, photo_key="chat/1/aaa.jpg")
        Message.objects.create(conversation=self.conversation, sender=self.ace_user, photo_key="chat/1/bbb.jpg")
        ConversationRead.objects.create(conversation=self.conversation, user=self.pat, last_read_id=2)

        GoogleIdentity.objects.create(user=self.pat, sub="google-pat")
        GoogleIdentity.objects.create(user=self.ace_user, sub="google-ace")
        DeviceToken.objects.create(user=self.pat, token="fcm-pat")
        DeviceToken.objects.create(user=self.ace_user, token="fcm-ace")
        DeviceToken.objects.create(user=self.sam, token="fcm-sam")
        ChatTermsAcceptance.objects.create(user=self.pat)
        Favorite.objects.create(user=self.pat, provider=self.ace)
        Favorite.objects.create(user=self.sam, provider=self.ace)
        UserBlock.objects.create(blocker=self.pat, blocked=self.sam)
        Notification.objects.create(device_id="device-pat", title="Welcome")
        Notification.objects.create(device_id="device-sam", title="Welcome")

        # Sam has a request and a conversation of their own that must never be touched.
        self.sam_request = ServiceRequest.objects.create(
            user=self.sam, category="plumbing", city="Edmonton", phone="+17805550177", consent_given=True,
            problem_description="Drain", location="T6E 1A1", device_id="device-sam",
        )
        self.sam_offer = self.make_offer(self.sam_request, self.ace, LeadOffer.STATUS_ACCEPTED)
        self.sam_conversation = Conversation.objects.create(offer=self.sam_offer)
        Message.objects.create(conversation=self.sam_conversation, sender=self.sam, body="Hello from Sam")

    def make_offer(self, request, provider, status, completed=False):
        offer = LeadOffer.objects.create(service_request=request, provider=provider)
        offer.status = status
        offer.sent_at = offer.responded_at = timezone.now()
        offer.hired = offer.job_completed = completed
        offer.save()
        return offer

    def delete_url(self):
        return reverse("accounts-delete")

    def post_delete(self, user, **body):
        body = body or {"confirm": "DELETE"}
        return self.client.post(self.delete_url(), body, content_type="application/json", **headers_for(user))


class DeleteEndpointTests(DeletionCase):
    def test_a_client_deletes_their_own_account(self):
        response = self.post_delete(self.pat)
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json(), {"deleted": True})

    def test_a_provider_deletes_their_own_account(self):
        self.assertEqual(self.post_delete(self.ace_user).status_code, 200)
        self.assertTrue(User.objects.get(pk=self.ace_user.pk).email.endswith(f"@{DELETED_EMAIL_DOMAIN}"))

    def test_the_word_must_be_typed(self):
        for body in ({}, {"confirm": ""}, {"confirm": "delete"}, {"confirm": "yes"}, {"confirm": True}, {"confirm": None}):
            with self.subTest(body=body):
                cache.clear()  # the endpoint allows 5 attempts an hour, and this makes six
                response = self.client.post(self.delete_url(), body, content_type="application/json", **headers_for(self.pat))
                self.assertEqual(response.status_code, 400)
        self.assertEqual(User.objects.get(pk=self.pat.pk).email, "pat@example.com")
        self.assertTrue(User.objects.get(pk=self.pat.pk).is_active)

    def test_it_needs_the_api_key_and_a_signed_in_person(self):
        body = {"confirm": "DELETE"}
        self.assertEqual(self.client.post(self.delete_url(), body, content_type="application/json").status_code, 401)
        no_key = {"HTTP_AUTHORIZATION": headers_for(self.pat)["HTTP_AUTHORIZATION"]}
        self.assertEqual(self.client.post(self.delete_url(), body, content_type="application/json", **no_key).status_code, 403)
        self.assertEqual(
            self.client.post(self.delete_url(), body, content_type="application/json", HTTP_X_API_KEY=KEY).status_code, 401
        )
        self.assertTrue(User.objects.get(pk=self.pat.pk).is_active)

    def test_it_only_ever_deletes_the_callers_own_account(self):
        self.post_delete(self.pat)
        self.assertEqual(User.objects.get(pk=self.sam.pk).email, "sam@example.com")
        self.assertEqual(User.objects.get(pk=self.ace_user.pk).email, "ace@example.com")

    def test_staff_accounts_are_refused(self):
        staff = account("boss@example.com", UserRole.ADMIN, "Boss")
        staff.is_staff = True
        staff.save()
        response = self.post_delete(staff)
        self.assertEqual(response.status_code, 403)
        self.assertTrue(User.objects.get(pk=staff.pk).is_active)
        self.assertEqual(User.objects.get(pk=staff.pk).email, "boss@example.com")

    def test_the_old_login_stops_working_straight_away(self):
        headers = headers_for(self.pat)
        refresh = str(RefreshToken.for_user(self.pat))
        self.post_delete(self.pat)
        me = self.client.get(reverse("accounts-me"), **headers)
        self.assertEqual(me.status_code, 401)
        renewed = self.client.post(
            reverse("accounts-token-refresh"), {"refresh": refresh}, content_type="application/json", HTTP_X_API_KEY=KEY
        )
        self.assertEqual(renewed.status_code, 401)

    def test_a_second_request_with_the_same_login_is_refused(self):
        headers = headers_for(self.pat)
        self.post_delete(self.pat)
        again = self.client.post(self.delete_url(), {"confirm": "DELETE"}, content_type="application/json", **headers)
        self.assertEqual(again.status_code, 401)
        self.assertEqual(AccountDeletion.objects.filter(user_id=self.pat.pk).count(), 1)

    def test_get_is_not_allowed(self):
        self.assertEqual(self.client.get(self.delete_url(), **headers_for(self.pat)).status_code, 405)

    def test_it_is_rate_limited(self):
        statuses = []
        for _ in range(7):
            statuses.append(
                self.client.post(self.delete_url(), {"confirm": "nope"}, content_type="application/json", **headers_for(self.pat)).status_code
            )
        self.assertIn(429, statuses)


class WhatHappensToAClientTests(DeletionCase):
    def setUp(self):
        super().setUp()
        self.post_delete(self.pat)
        self.pat.refresh_from_db()

    def test_nothing_on_the_account_names_them_any_more(self):
        self.assertEqual(self.pat.email, f"deleted-{self.pat.pk}@{DELETED_EMAIL_DOMAIN}")
        self.assertEqual(self.pat.username, f"deleted-{self.pat.pk}")
        self.assertEqual((self.pat.first_name, self.pat.last_name), ("", ""))
        self.assertFalse(self.pat.is_active)
        self.assertFalse(self.pat.has_usable_password())
        self.assertEqual(UserProfile.objects.get(user=self.pat).full_name, "")
        self.assertNotIn("Pat", str(UserProfile.objects.get(user=self.pat)))

    def test_their_google_link_push_tokens_saved_providers_blocks_and_chat_agreement_are_gone(self):
        self.assertFalse(GoogleIdentity.objects.filter(user=self.pat).exists())
        self.assertFalse(DeviceToken.objects.filter(user=self.pat).exists())
        self.assertFalse(Favorite.objects.filter(user=self.pat).exists())
        self.assertFalse(UserBlock.objects.filter(blocker=self.pat).exists())
        self.assertFalse(ChatTermsAcceptance.objects.filter(user=self.pat).exists())
        self.assertFalse(ConversationRead.objects.filter(user=self.pat).exists())

    def test_their_chats_and_every_message_in_them_are_gone(self):
        self.assertFalse(Conversation.objects.filter(pk=self.conversation.pk).exists())
        self.assertFalse(Message.objects.filter(conversation_id=self.conversation.pk).exists())
        self.assertFalse(Message.objects.filter(body__icontains="Elm St").exists())

    def test_the_details_of_their_requests_are_blanked_but_the_request_stays(self):
        request = ServiceRequest.objects.get(pk=self.request.pk)
        self.assertEqual(
            (request.phone, request.problem_description, request.location, request.device_id), ("", "", "", "")
        )
        self.assertEqual((request.required_skills, request.required_equipment, request.required_qualifications), ([], [], []))
        # what is kept is only what says what kind of request it was
        self.assertEqual((request.category, request.city, request.urgency), ("plumbing", "Edmonton", "today"))
        self.assertEqual(request.user_id, self.pat.pk)  # the (anonymous) account

    def test_their_notifications_are_removed_and_others_are_not(self):
        self.assertFalse(Notification.objects.filter(device_id="device-pat").exists())
        self.assertTrue(Notification.objects.filter(device_id="device-sam").exists())

    def test_the_lead_offer_is_kept(self):
        offer = LeadOffer.objects.get(pk=self.offer.pk)
        self.assertEqual((offer.status, offer.job_completed, offer.provider_id), (LeadOffer.STATUS_ACCEPTED, True, self.ace.pk))

    def test_the_review_they_wrote_is_kept_with_no_name(self):
        review = Review.objects.get(pk=self.review.pk)
        self.assertEqual((review.rating, review.comment, review.reply), (5, "Great work", ""))
        page = self.client.get(reverse("provider-reviews", args=[self.ace.pk]), **headers_for(self.sam))
        shown = page.json()["reviews"][0]
        self.assertEqual(shown["client_name"], "A client")
        self.assertNotIn("Pat", page.content.decode())
        self.assertEqual(page.json()["provider"]["review_count"], 1)

    def test_text_they_typed_when_reporting_is_removed_but_the_report_stays(self):
        # (set up and checked here: the shared setUp already deleted the account)
        other = account("reporter@example.com", UserRole.CUSTOMER, "Reporter")
        review = Review.objects.create(
            offer=self.make_offer(
                ServiceRequest.objects.create(user=other, category="plumbing", city="Edmonton", phone="+17805550166", consent_given=True),
                self.ace, LeadOffer.STATUS_ACCEPTED, completed=True,
            ),
            client=other, provider=self.ace, rating=3,
        )
        report = ReviewReport.objects.create(review=review, reporter=other, reason="spam", details="It was my neighbour Pat Smith")
        delete_account(other)
        report.refresh_from_db()
        self.assertEqual((report.details, report.reason), ("", "spam"))

    def test_other_peoples_data_is_untouched(self):
        sam_request = ServiceRequest.objects.get(pk=self.sam_request.pk)
        self.assertEqual((sam_request.phone, sam_request.problem_description, sam_request.location), ("+17805550177", "Drain", "T6E 1A1"))
        self.assertTrue(Conversation.objects.filter(pk=self.sam_conversation.pk).exists())
        self.assertTrue(Message.objects.filter(body="Hello from Sam").exists())
        self.assertTrue(DeviceToken.objects.filter(user=self.sam).exists())
        self.assertTrue(Favorite.objects.filter(user=self.sam).exists())
        self.assertEqual(User.objects.get(pk=self.sam.pk).email, "sam@example.com")
        self.assertEqual(ProviderProfile.objects.get(pk=self.ace.pk).business_name, "Ace Plumbing")

    def test_the_deletion_is_recorded_without_any_personal_data(self):
        record = AccountDeletion.objects.get(user_id=self.pat.pk)
        self.assertEqual((record.role, record.via), ("customer", "app"))
        fields = {f.name for f in AccountDeletion._meta.get_fields()}
        self.assertEqual(fields, {"id", "user_id", "role", "via", "deleted_at"})

    def test_they_can_come_back_as_a_brand_new_account(self):
        google = GoogleUser(sub="google-pat", email="pat@example.com", name="Pat Client")
        user, created = user_for_google(google, UserRole.CUSTOMER)
        self.assertTrue(created)
        self.assertNotEqual(user.pk, self.pat.pk)
        self.assertTrue(user.is_active)
        self.assertFalse(ServiceRequest.objects.filter(user=user).exists())
        self.assertFalse(Review.objects.filter(client=user).exists())


class WhatHappensToAProviderTests(DeletionCase):
    def setUp(self):
        super().setUp()
        self.pending = self.make_offer(
            ServiceRequest.objects.create(user=self.sam, category="plumbing", city="Edmonton", phone="+17805550177", consent_given=True),
            self.ace, LeadOffer.STATUS_SENT,
        )
        self.post_delete(self.ace_user)
        self.ace.refresh_from_db()
        self.ace_user.refresh_from_db()

    def test_the_profile_becomes_an_anonymous_shell(self):
        ace = self.ace
        self.assertEqual(ace.business_name, DELETED_PROVIDER_NAME)
        self.assertEqual((ace.phone, ace.email, ace.bio, ace.notes, ace.review_note), ("", "", "", "", ""))
        self.assertEqual((ace.cities, ace.waitlist_cities), ([], []))
        self.assertEqual(list(ace.categories.all()), [])
        self.assertTrue(ace.sms_opt_out, "their number is never texted again")
        self.assertEqual(ace.status, ProviderProfile.STATUS_REJECTED)
        self.assertIsNotNone(ace.sms_consent_at, "the record that consent was once given is kept")

    def test_the_account_is_anonymous_and_cannot_sign_in(self):
        self.assertEqual(self.ace_user.email, f"deleted-{self.ace_user.pk}@{DELETED_EMAIL_DOMAIN}")
        self.assertFalse(self.ace_user.is_active)
        self.assertFalse(GoogleIdentity.objects.filter(user=self.ace_user).exists())
        self.assertFalse(DeviceToken.objects.filter(user=self.ace_user).exists())

    def test_their_chats_are_gone_including_the_clients_side(self):
        self.assertFalse(Conversation.objects.filter(pk=self.conversation.pk).exists())
        self.assertFalse(Conversation.objects.filter(pk=self.sam_conversation.pk).exists())
        self.assertFalse(Message.objects.exists())

    def test_clients_no_longer_see_them_or_can_save_them(self):
        self.assertFalse(Favorite.objects.filter(provider=self.ace).exists())
        page = self.client.get(reverse("provider-reviews", args=[self.ace.pk]), **headers_for(self.sam))
        self.assertEqual(page.status_code, 404)
        self.assertEqual(self.client.put(reverse("favorite", args=[self.ace.pk]), **headers_for(self.sam)).status_code, 404)
        self.assertEqual(self.client.get(reverse("favorites"), **headers_for(self.sam)).json()["favorites"], [])

    def test_their_replies_to_reviews_are_removed_and_the_reviews_and_ratings_stay(self):
        review = Review.objects.get(pk=self.review.pk)
        self.assertEqual((review.rating, review.comment, review.reply, review.reply_at), (5, "Great work", "", None))

    def test_offers_stay_but_open_ones_are_closed_so_nobody_is_asked_to_answer(self):
        self.assertEqual(LeadOffer.objects.get(pk=self.offer.pk).status, LeadOffer.STATUS_ACCEPTED)
        self.assertEqual(LeadOffer.objects.get(pk=self.pending.pk).status, LeadOffer.STATUS_EXPIRED)
        self.assertEqual(LeadOffer.objects.filter(provider=self.ace).count(), 3)

    def test_they_never_appear_in_matches(self):
        self.assertEqual(ProviderProfile.objects.approved().filter(pk=self.ace.pk).count(), 0)

    def test_the_clients_own_data_is_untouched(self):
        self.assertEqual(ServiceRequest.objects.get(pk=self.request.pk).phone, "+17805550199")
        self.assertEqual(User.objects.get(pk=self.pat.pk).email, "pat@example.com")
        self.assertTrue(DeviceToken.objects.filter(user=self.pat).exists())

    def test_the_deletion_is_recorded(self):
        self.assertEqual(AccountDeletion.objects.get(user_id=self.ace_user.pk).role, "provider")


class OpenRequestsAndJobsTests(DeletionCase):
    def test_a_request_still_waiting_for_an_answer_is_closed_when_the_client_leaves(self):
        waiting_request = ServiceRequest.objects.create(
            user=self.pat, category="plumbing", city="Edmonton", phone="+17805550199", consent_given=True
        )
        waiting = self.make_offer(waiting_request, self.ace, LeadOffer.STATUS_SENT)
        pending = LeadOffer.objects.create(service_request=waiting_request, provider=ProviderProfile.objects.create(
            user=account("other@example.com", UserRole.PROVIDER, "Other"), business_name="Other Co", phone="+17805550102",
            email="other@example.com", status=ProviderProfile.STATUS_APPROVED,
        ))
        delete_account(self.pat)
        waiting.refresh_from_db()
        pending.refresh_from_db()
        self.assertEqual((waiting.status, pending.status), (LeadOffer.STATUS_EXPIRED, LeadOffer.STATUS_EXPIRED))
        answer = self.client.post(
            f"/api/provider/leads/{waiting.pk}/accept/", {}, content_type="application/json", **headers_for(self.ace_user)
        )
        self.assertEqual(answer.status_code, 409, "the provider can no longer accept it")

    def test_a_provider_cannot_open_a_chat_with_a_deleted_client(self):
        delete_account(self.pat)
        response = self.client.post(
            reverse("conversation-open"), {"offer_id": self.offer.pk}, content_type="application/json", **headers_for(self.ace_user)
        )
        self.assertEqual(response.status_code, 404)

    def test_a_client_cannot_open_a_chat_with_a_deleted_provider(self):
        delete_account(self.ace_user)
        response = self.client.post(
            reverse("conversation-open"), {"offer_id": self.sam_offer.pk}, content_type="application/json", **headers_for(self.sam)
        )
        self.assertEqual(response.status_code, 404)

    def test_the_other_person_no_longer_sees_the_deleted_chat_in_their_list(self):
        delete_account(self.pat)
        listed = self.client.get(reverse("conversation-list"), **headers_for(self.ace_user)).json()["conversations"]
        self.assertEqual([c["offer_id"] for c in listed], [self.sam_offer.pk])

    def test_no_no_yes_alert_is_sent_for_a_deleted_clients_request(self):
        stale = ServiceRequest.objects.create(
            user=self.pat, category="plumbing", city="Edmonton", phone="+17805550199", consent_given=True
        )
        offer = LeadOffer.objects.create(service_request=stale, provider=self.ace)
        offer.mark_sent(now=timezone.now() - timedelta(hours=5))
        delete_account(self.pat)
        with patch("leads.jobs.notify_admin") as notify:
            self.assertEqual(jobs.alert_requests_without_yes(), 0)
        notify.assert_not_called()

    def test_no_reminder_email_goes_to_a_deleted_client(self):
        self.offer.job_completed = False
        self.offer.responded_at = timezone.now() - timedelta(days=10)
        self.offer.save()
        delete_account(self.pat)
        with patch("leads.jobs.notify_user") as notify:
            self.assertEqual(jobs.send_completion_reminders(), 0)
        notify.assert_not_called()


@override_settings(**R2)
class ChatPhotoTests(DeletionCase):
    def test_the_photos_in_the_conversation_are_removed_from_storage(self):
        with patch("messaging.storage.delete") as remove:
            summary = delete_account(self.pat)
        removed = sorted(call.args[0] for call in remove.call_args_list)
        self.assertEqual(removed, ["chat/1/aaa.jpg", "chat/1/bbb.jpg"])
        self.assertEqual((summary.photos_found, summary.photos_deleted, summary.photos_waiting), (2, 2, 0))
        self.assertFalse(PhotoDeletion.objects.exists(), "nothing is left waiting")

    def test_other_peoples_photos_are_not_touched(self):
        Message.objects.create(conversation=self.sam_conversation, sender=self.sam, photo_key="chat/2/sam.jpg")
        with patch("messaging.storage.delete") as remove:
            delete_account(self.pat)
        self.assertNotIn("chat/2/sam.jpg", [call.args[0] for call in remove.call_args_list])

    def test_a_photo_that_cannot_be_deleted_stays_queued_and_is_retried(self):
        with patch("messaging.storage.delete", side_effect=OSError("bucket unreachable")):
            summary = delete_account(self.pat)
        self.assertEqual((summary.photos_deleted, summary.photos_waiting), (0, 2))
        queued = PhotoDeletion.objects.order_by("key")
        self.assertEqual([p.key for p in queued], ["chat/1/aaa.jpg", "chat/1/bbb.jpg"])
        self.assertEqual({p.attempts for p in queued}, {1})
        self.assertEqual({p.last_error for p in queued}, {"OSError"})
        # the account is deleted regardless
        self.assertFalse(User.objects.get(pk=self.pat.pk).is_active)

        with patch("messaging.storage.delete") as remove:
            out = StringIO()
            call_command("purge_photo_queue", stdout=out)
        self.assertEqual(remove.call_count, 2)
        self.assertFalse(PhotoDeletion.objects.exists())
        self.assertIn("Deleted 2 photo(s); 0 still queued.", out.getvalue())

    def test_one_failure_does_not_stop_the_others(self):
        def flaky(key):
            if key.endswith("aaa.jpg"):
                raise OSError("nope")

        with patch("messaging.storage.delete", side_effect=flaky):
            summary = delete_account(self.pat)
        self.assertEqual((summary.photos_deleted, summary.photos_waiting), (1, 1))
        self.assertEqual([p.key for p in PhotoDeletion.objects.all()], ["chat/1/aaa.jpg"])

    def test_the_queue_command_is_safe_to_run_when_there_is_nothing_to_do(self):
        out = StringIO()
        call_command("purge_photo_queue", stdout=out)
        self.assertIn("Deleted 0 photo(s); 0 still queued.", out.getvalue())

    def test_a_key_is_only_ever_queued_once(self):
        photo_queue.queue_photos(["chat/9/x.jpg", "chat/9/x.jpg"])
        photo_queue.queue_photos(["chat/9/x.jpg", ""])
        self.assertEqual(PhotoDeletion.objects.count(), 1)


class WithoutStorageTests(DeletionCase):
    @override_settings(R2_ACCOUNT_ID="", R2_ACCESS_KEY_ID="", R2_SECRET_ACCESS_KEY="", R2_BUCKET="")
    def test_with_no_bucket_configured_the_keys_wait_instead_of_being_forgotten(self):
        summary = delete_account(self.pat)
        self.assertEqual((summary.photos_deleted, summary.photos_waiting), (0, 2))
        self.assertEqual(PhotoDeletion.objects.count(), 2)
        out = StringIO()
        call_command("purge_photo_queue", stdout=out)
        self.assertIn("not configured", out.getvalue())
        self.assertEqual(PhotoDeletion.objects.count(), 2)


class AllOrNothingTests(DeletionCase):
    def test_if_something_fails_nothing_is_deleted(self):
        with patch("accounts.deletion.AccountDeletion.objects.create", side_effect=RuntimeError("boom")):
            with self.assertRaises(RuntimeError):
                delete_account(self.pat)
        self.pat.refresh_from_db()
        self.assertEqual(self.pat.email, "pat@example.com")
        self.assertTrue(self.pat.is_active)
        self.assertTrue(Conversation.objects.filter(pk=self.conversation.pk).exists())
        self.assertEqual(Message.objects.filter(conversation=self.conversation).count(), 4)
        self.assertTrue(DeviceToken.objects.filter(user=self.pat).exists())
        self.assertEqual(ServiceRequest.objects.get(pk=self.request.pk).phone, "+17805550199")
        self.assertFalse(PhotoDeletion.objects.exists(), "the queue is rolled back too")
        self.assertFalse(AccountDeletion.objects.exists())

    def test_deleting_twice_does_nothing_the_second_time(self):
        first = delete_account(self.pat)
        second = delete_account(User.objects.get(pk=self.pat.pk))
        self.assertFalse(first.already_deleted)
        self.assertTrue(second.already_deleted)
        self.assertEqual(AccountDeletion.objects.count(), 1)

    def test_an_account_with_no_profile_or_data_can_still_be_deleted(self):
        bare = User.objects.create_user(username="bare@example.com", email="bare@example.com")
        summary = delete_account(bare)
        self.assertEqual((summary.conversations, summary.messages), (0, 0))
        bare.refresh_from_db()
        self.assertFalse(bare.is_active)
        self.assertEqual(AccountDeletion.objects.get(user_id=bare.pk).role, "")

    def test_staff_cannot_be_deleted_by_the_service_either(self):
        staff = User.objects.create_superuser(username="root", email="root@example.com", password="x")
        with self.assertRaises(AccountNotDeletable):
            delete_account(staff)


class AdminActionTests(DeletionCase):
    def setUp(self):
        super().setUp()
        self.staff = User.objects.create_superuser(username="boss", email="boss@example.com", password="x")
        self.client.force_login(self.staff)
        self.url = reverse("admin:accounts_userprofile_changelist")
        self.profile = UserProfile.objects.get(user=self.pat)

    def run_action(self, profiles, confirm=False):
        data = {"action": "delete_accounts", "_selected_action": [p.pk for p in profiles]}
        if confirm:
            data["confirm_delete"] = "yes"
        else:
            data["index"] = "0"
        return self.client.post(self.url, data)

    def test_it_asks_first_and_deletes_nothing_until_confirmed(self):
        response = self.run_action([self.profile])
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "This cannot be undone")
        self.assertContains(response, "pat@example.com")
        self.assertContains(response, "Yes, delete these accounts")
        self.assertEqual(User.objects.get(pk=self.pat.pk).email, "pat@example.com")
        self.assertFalse(AccountDeletion.objects.exists())

    def test_confirming_deletes_the_account_and_says_so(self):
        response = self.run_action([self.profile], confirm=True)
        self.assertEqual(response.status_code, 302)
        self.assertEqual(AccountDeletion.objects.get(user_id=self.pat.pk).via, "admin")
        self.assertFalse(User.objects.get(pk=self.pat.pk).is_active)
        follow = self.client.get(self.url)
        self.assertContains(follow, "Deleted 1 account(s). Skipped 0")

    def test_staff_and_already_deleted_accounts_are_skipped(self):
        staff_profile = UserProfile.objects.create(user=self.staff, role=UserRole.ADMIN)
        self.run_action([self.profile], confirm=True)
        response = self.run_action([self.profile, staff_profile], confirm=True)
        self.assertEqual(response.status_code, 302)
        self.assertEqual(User.objects.get(pk=self.staff.pk).email, "boss@example.com")
        self.assertEqual(AccountDeletion.objects.count(), 1)

    def test_the_deletion_record_page_loads_and_cannot_be_edited(self):
        delete_account(self.pat)
        page = self.client.get(reverse("admin:accounts_accountdeletion_changelist"))
        self.assertEqual(page.status_code, 200)
        self.assertNotContains(page, "pat@example.com")
        record = AccountDeletion.objects.get()
        self.assertEqual(self.client.post(reverse("admin:accounts_accountdeletion_delete", args=[record.pk]), {"post": "yes"}).status_code, 403)

    def test_the_photo_queue_page_loads(self):
        self.assertEqual(self.client.get(reverse("admin:messaging_photodeletion_changelist")).status_code, 200)


class CommandTests(DeletionCase):
    def run_command(self, *args):
        out = StringIO()
        call_command("delete_account", *args, stdout=out)
        return out.getvalue()

    def test_without_yes_it_only_says_what_it_would_do(self):
        text = self.run_command("--email", "pat@example.com")
        self.assertIn("Would delete the customer account", text)
        self.assertEqual(User.objects.get(pk=self.pat.pk).email, "pat@example.com")

    def test_with_yes_it_deletes(self):
        text = self.run_command("--email", "PAT@example.com", "--yes")
        self.assertIn("Deleted account", text)
        self.assertIn("4 message(s)", text)
        self.assertEqual(AccountDeletion.objects.get(user_id=self.pat.pk).via, "command")

    def test_running_it_again_says_it_is_already_done(self):
        self.run_command("--email", "pat@example.com", "--yes")
        with self.assertRaises(CommandError):
            self.run_command("--email", "pat@example.com", "--yes")  # the email no longer exists

    def test_an_unknown_email_is_an_error(self):
        with self.assertRaises(CommandError):
            self.run_command("--email", "nobody@example.com", "--yes")

    def test_staff_are_refused(self):
        User.objects.create_superuser(username="root", email="root@example.com", password="x")
        with self.assertRaises(CommandError):
            self.run_command("--email", "root@example.com", "--yes")


@override_settings(**R2)
class PhotoRetryJobTests(DeletionCase):
    """The 15-minute jobs command retries photos an earlier delete could not remove."""

    def test_the_jobs_retry_queued_photos(self):
        with patch("messaging.storage.delete", side_effect=OSError("down")):
            delete_account(self.pat)
        self.assertEqual(PhotoDeletion.objects.count(), 2)
        with patch("messaging.storage.delete") as remove:
            result = jobs.run_all()
        self.assertEqual(result["photos_removed"], 2)
        self.assertEqual(remove.call_count, 2)
        self.assertFalse(PhotoDeletion.objects.exists())

    def test_with_nothing_queued_it_does_nothing(self):
        self.assertEqual(jobs.run_all()["photos_removed"], 0)

    def test_a_storage_problem_never_stops_the_other_jobs(self):
        with patch("messaging.photo_queue.purge", side_effect=RuntimeError("boom")):
            result = jobs.run_all()
        self.assertEqual(result["photos_removed"], 0)
        self.assertIn("offers_expired", result)

    def test_the_config_check_says_when_photos_are_waiting(self):
        with patch("messaging.storage.delete", side_effect=OSError("down")):
            delete_account(self.pat)
        out = StringIO()
        call_command("check_messaging_config", stdout=out)
        self.assertIn("2 photo(s) of deleted accounts still to remove", out.getvalue())
        PhotoDeletion.objects.all().delete()
        out = StringIO()
        call_command("check_messaging_config", stdout=out)
        self.assertIn("none waiting", out.getvalue())
