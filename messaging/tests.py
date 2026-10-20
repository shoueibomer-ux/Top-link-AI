import json
from unittest.mock import MagicMock, patch

from botocore.exceptions import ClientError
from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase, override_settings
from django.utils import timezone
from io import StringIO
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import UserProfile, UserRole
from leads.models import LeadOffer
from provider_search.models import ServiceRequest
from providers.models import ProviderProfile

from . import push, storage
from .models import (
    ChatTermsAcceptance,
    Conversation,
    ConversationRead,
    DeviceToken,
    Message,
    MessageReport,
    UserBlock,
)

User = get_user_model()
KEY = "test-key"
FAKE_FCM = json.dumps({"project_id": "demo-proj", "client_email": "svc@demo-proj.iam.gserviceaccount.com", "private_key": "PRIVATE-KEY-MUST-NEVER-BE-PRINTED"})
R2 = dict(R2_ACCOUNT_ID="acct123", R2_ACCESS_KEY_ID="AKIAFAKE", R2_SECRET_ACCESS_KEY="shh-secret", R2_BUCKET="chat-bucket")


def account(email, role, name):
    user = User.objects.create_user(username=email, email=email)
    UserProfile.objects.create(user=user, role=role, full_name=name)
    token = RefreshToken.for_user(user).access_token
    return user, {"HTTP_X_API_KEY": KEY, "HTTP_AUTHORIZATION": f"Bearer {token}"}


@override_settings(API_KEY=KEY)
class ChatCase(TestCase):
    """A client, a provider who accepted their request, and two strangers (one of each kind)."""

    def setUp(self):
        cache.delete_pattern("rl:*")
        self.client_user, self.client_h = account("client@example.com", UserRole.CUSTOMER, "Pat Client")
        self.provider_user, self.provider_h = account("ace@example.com", UserRole.PROVIDER, "Alex Owner")
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user, business_name="Ace Plumbing", phone="+17805550101", email="ace@example.com",
            status=ProviderProfile.STATUS_APPROVED,
        )
        self.request_obj = ServiceRequest.objects.create(
            user=self.client_user, category="plumbing", city="Edmonton", phone="+17805550199", consent_given=True
        )
        self.offer = self.make_offer(self.provider)
        self.stranger_client, self.stranger_client_h = account("nosy@example.com", UserRole.CUSTOMER, "Nosy Neighbour")
        self.stranger_provider_user, self.stranger_provider_h = account("other@example.com", UserRole.PROVIDER, "Other Owner")
        ProviderProfile.objects.create(
            user=self.stranger_provider_user, business_name="Other Co", phone="+17805550102", email="other@example.com",
            status=ProviderProfile.STATUS_APPROVED,
        )
        self.conversation = Conversation.objects.create(offer=self.offer)

    def make_offer(self, provider, status=LeadOffer.STATUS_ACCEPTED, request=None):
        offer = LeadOffer.objects.create(service_request=request or self.request_obj, provider=provider)
        offer.status = status
        offer.sent_at = offer.responded_at = timezone.now()
        offer.save()
        return offer

    def agree(self, *users):
        for user in users:
            ChatTermsAcceptance.objects.get_or_create(user=user)

    def url(self, name, *args):
        from django.urls import reverse

        return reverse(name, args=args)

    def post(self, name, headers, *args, **body):
        return self.client.post(self.url(name, *args), body, content_type="application/json", **headers)

    def say(self, user, text="Hello", conversation=None):
        return Message.objects.create(conversation=conversation or self.conversation, sender=user, body=text)


# ---------------------------------------------------------------------------------------------------
class PermissionTests(ChatCase):
    """No one can read, write in, report in, block in or call from a conversation they are not part of."""

    def requests_for(self, conversation_id, message_id):
        c = conversation_id
        return {
            "read messages": ("get", self.url("conversation-messages", c), None),
            "send message": ("post", self.url("conversation-messages", c), {"body": "hi"}),
            "mark read": ("post", self.url("conversation-read", c), {}),
            "upload photo": ("post", self.url("conversation-photo-upload", c), {"content_type": "image/jpeg"}),
            "block": ("post", self.url("conversation-block", c), {}),
            "unblock": ("delete", self.url("conversation-block", c), {}),
            "call": ("get", self.url("conversation-call", c), None),
            "report": ("post", self.url("message-report", c, message_id), {"reason": "spam"}),
        }

    def call(self, method, url, body, headers):
        if body is None:
            return getattr(self.client, method)(url, **headers)
        return getattr(self.client, method)(url, body, content_type="application/json", **headers)

    def test_strangers_get_a_404_on_every_endpoint_and_change_nothing(self):
        self.agree(self.stranger_client, self.stranger_provider_user)
        message = self.say(self.provider_user, "Private details")
        for who, headers in (("another client", self.stranger_client_h), ("another provider", self.stranger_provider_h)):
            for what, (method, url, body) in self.requests_for(self.conversation.id, message.id).items():
                with self.subTest(who=who, action=what):
                    response = self.call(method, url, body, headers)
                    self.assertEqual(response.status_code, 404, response.content)
                    self.assertNotIn("Private details", response.content.decode())
        self.assertEqual(Message.objects.count(), 1)
        self.assertFalse(MessageReport.objects.exists())
        self.assertFalse(UserBlock.objects.exists())
        self.assertFalse(ConversationRead.objects.exists())

    def test_a_stranger_gets_the_same_answer_as_for_a_conversation_that_does_not_exist(self):
        real = self.client.get(self.url("conversation-messages", self.conversation.id), **self.stranger_client_h)
        missing = self.client.get(self.url("conversation-messages", 999999), **self.stranger_client_h)
        self.assertEqual((real.status_code, real.json()), (missing.status_code, missing.json()))

    def test_signing_in_and_the_api_key_are_both_required(self):
        url = self.url("conversation-messages", self.conversation.id)
        self.assertEqual(self.client.get(url, HTTP_X_API_KEY=KEY).status_code, 401)  # no login
        self.assertEqual(self.client.get(url).status_code, 401)  # nothing at all
        no_key = {"HTTP_AUTHORIZATION": self.client_h["HTTP_AUTHORIZATION"]}
        self.assertEqual(self.client.get(url, **no_key).status_code, 403)  # login but no key

    def test_both_people_in_the_conversation_can_read_it(self):
        self.say(self.client_user, "From the client")
        for headers in (self.client_h, self.provider_h):
            response = self.client.get(self.url("conversation-messages", self.conversation.id), **headers)
            self.assertEqual(response.status_code, 200)
            self.assertEqual([m["body"] for m in response.json()["messages"]], ["From the client"])

    def test_a_stranger_cannot_open_a_chat_for_someone_elses_offer(self):
        Conversation.objects.all().delete()
        for headers in (self.stranger_client_h, self.stranger_provider_h):
            response = self.post("conversation-open", headers, offer_id=self.offer.id)
            self.assertEqual(response.status_code, 404)
        self.assertFalse(Conversation.objects.exists())

    def test_the_conversation_list_only_holds_your_own(self):
        other_request = ServiceRequest.objects.create(
            user=self.stranger_client, category="plumbing", city="Edmonton", phone="+17805550177", consent_given=True
        )
        stranger_provider = ProviderProfile.objects.get(user=self.stranger_provider_user)
        other_offer = self.make_offer(stranger_provider, request=other_request)
        other_conversation = Conversation.objects.create(offer=other_offer)
        self.say(self.stranger_client, "Not for you", other_conversation)

        mine = self.client.get(self.url("conversation-list"), **self.client_h).json()["conversations"]
        self.assertEqual([c["id"] for c in mine], [self.conversation.id])
        theirs = self.client.get(self.url("conversation-list"), **self.stranger_client_h).json()["conversations"]
        self.assertEqual([c["id"] for c in theirs], [other_conversation.id])
        self.assertNotIn("Not for you", json.dumps(mine))

    def test_a_request_with_no_signed_in_owner_has_no_chat_for_anyone(self):
        orphan = ServiceRequest.objects.create(category="plumbing", city="Edmonton", phone="+17805550166", consent_given=True)
        offer = self.make_offer(self.provider, request=orphan)
        # There is no client to talk to, so not even the provider on that offer gets a chat.
        for headers in (self.provider_h, self.stranger_client_h):
            self.assertEqual(self.post("conversation-open", headers, offer_id=offer.id).status_code, 404)
        self.assertEqual(Conversation.objects.filter(offer=offer).count(), 0)


# ---------------------------------------------------------------------------------------------------
class OpenConversationTests(ChatCase):
    def setUp(self):
        super().setUp()
        Conversation.objects.all().delete()

    def test_either_person_can_open_the_chat_for_an_accepted_offer_and_it_is_created_once(self):
        first = self.post("conversation-open", self.client_h, offer_id=self.offer.id)
        self.assertEqual(first.status_code, 200)
        second = self.post("conversation-open", self.provider_h, offer_id=self.offer.id)
        self.assertEqual(Conversation.objects.count(), 1)
        self.assertEqual(first.json()["id"], second.json()["id"])
        self.assertEqual(first.json()["other_name"], "Ace Plumbing")  # the client sees the business
        self.assertEqual(second.json()["other_name"], "Pat C.")  # the provider sees a shortened name

    def test_the_chat_says_what_it_is_about(self):
        self.request_obj.problem_description = "Leaking kitchen sink"
        self.request_obj.save()
        client_view = self.post("conversation-open", self.client_h, offer_id=self.offer.id).json()
        provider_view = self.post("conversation-open", self.provider_h, offer_id=self.offer.id).json()
        self.assertEqual(client_view["request_summary"], "Plumbing · Leaking kitchen sink")
        self.assertEqual(provider_view["request_summary"], "Plumbing · Leaking kitchen sink")

    def test_without_a_description_it_is_just_the_service(self):
        data = self.post("conversation-open", self.client_h, offer_id=self.offer.id).json()
        self.assertEqual(data["request_summary"], "Plumbing")

    def test_a_long_description_is_cut_short_on_one_line(self):
        self.request_obj.problem_description = "Water  everywhere\nin the basement " + "and rising " * 20
        self.request_obj.save()
        summary = self.post("conversation-open", self.client_h, offer_id=self.offer.id).json()["request_summary"]
        self.assertTrue(summary.startswith("Plumbing · Water everywhere in the basement"))
        self.assertTrue(summary.endswith("…"))
        self.assertNotIn("\n", summary)
        self.assertLessEqual(len(summary), len("Plumbing · ") + 60)

    def test_the_summary_is_in_the_list_and_the_message_page_too(self):
        self.request_obj.problem_description = "Leaking kitchen sink"
        self.request_obj.save()
        opened = self.post("conversation-open", self.client_h, offer_id=self.offer.id).json()
        listed = self.client.get(self.url("conversation-list"), **self.client_h).json()["conversations"]
        self.assertEqual(listed[0]["request_summary"], "Plumbing · Leaking kitchen sink")
        page = self.client.get(self.url("conversation-messages", opened["id"]), **self.provider_h).json()
        self.assertEqual(page["request_summary"], "Plumbing · Leaking kitchen sink")

    def test_a_service_missing_from_the_catalog_falls_back_to_the_slug(self):
        from provider_search.models import ServiceRequest as SR

        SR.objects.filter(pk=self.request_obj.pk).update(category="old-service")
        data = self.post("conversation-open", self.client_h, offer_id=self.offer.id).json()
        self.assertEqual(data["request_summary"], "Old Service")

    def test_only_an_accepted_offer_has_a_chat(self):
        for status in (LeadOffer.STATUS_PENDING, LeadOffer.STATUS_SENT, LeadOffer.STATUS_DECLINED, LeadOffer.STATUS_EXPIRED):
            with self.subTest(status=status):
                other = ProviderProfile.objects.create(
                    user=account(f"{status}@example.com", UserRole.PROVIDER, "X")[0], business_name=f"P {status}",
                    phone="+17805550150", email=f"{status}@example.com", status=ProviderProfile.STATUS_APPROVED,
                )
                offer = self.make_offer(other, status=status)
                self.assertEqual(self.post("conversation-open", self.client_h, offer_id=offer.id).status_code, 404)
        self.assertFalse(Conversation.objects.exists())

    def test_a_bad_offer_id_is_a_404_not_a_server_error(self):
        for value in (None, "x", True, [1], 999999):
            with self.subTest(offer_id=value):
                self.assertEqual(self.post("conversation-open", self.client_h, offer_id=value).status_code, 404)


# ---------------------------------------------------------------------------------------------------
class MessagesTests(ChatCase):
    def test_messages_come_oldest_first_with_who_wrote_them(self):
        self.say(self.client_user, "one")
        self.say(self.provider_user, "two")
        data = self.client.get(self.url("conversation-messages", self.conversation.id), **self.client_h).json()
        self.assertEqual([(m["body"], m["mine"]) for m in data["messages"]], [("one", True), ("two", False)])
        self.assertEqual(data["other_name"], "Ace Plumbing")
        self.assertTrue(data["can_send"])
        provider_view = self.client.get(self.url("conversation-messages", self.conversation.id), **self.provider_h).json()
        self.assertEqual([m["mine"] for m in provider_view["messages"]], [False, True])

    def test_since_id_returns_only_newer_messages(self):
        first = self.say(self.client_user, "one")
        self.say(self.provider_user, "two")
        self.say(self.client_user, "three")
        data = self.client.get(self.url("conversation-messages", self.conversation.id), {"since_id": first.id}, **self.client_h).json()
        self.assertEqual([m["body"] for m in data["messages"]], ["two", "three"])
        none = self.client.get(self.url("conversation-messages", self.conversation.id), {"since_id": 10**9}, **self.client_h).json()
        self.assertEqual(none["messages"], [])
        self.assertEqual(self.client.get(self.url("conversation-messages", self.conversation.id), {"since_id": "x"}, **self.client_h).status_code, 400)

    def test_without_since_id_you_get_the_latest_page(self):
        for i in range(60):
            self.say(self.client_user, f"m{i}")
        data = self.client.get(self.url("conversation-messages", self.conversation.id), **self.client_h).json()
        self.assertEqual(len(data["messages"]), 50)
        self.assertEqual(data["messages"][-1]["body"], "m59")
        self.assertEqual(data["messages"][0]["body"], "m10")

    def test_a_hidden_message_shows_as_removed_and_its_text_is_never_sent(self):
        message = self.say(self.provider_user, "Something nasty")
        message.hidden = True
        message.save()
        for headers in (self.client_h, self.provider_h):
            response = self.client.get(self.url("conversation-messages", self.conversation.id), **headers)
            (shown,) = response.json()["messages"]
            self.assertTrue(shown["removed"])
            self.assertEqual((shown["body"], shown["photo_url"]), ("", None))
            self.assertNotIn("Something nasty", response.content.decode())

    def test_sending_needs_the_chat_rules_to_be_agreed_first(self):
        response = self.post("conversation-messages", self.client_h, self.conversation.id, body="hi")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["code"], "terms_required")
        self.assertFalse(Message.objects.exists())
        accepted = self.client.post(self.url("chat-terms"), {}, content_type="application/json", **self.client_h)
        self.assertTrue(accepted.json()["accepted"])
        self.assertEqual(self.post("conversation-messages", self.client_h, self.conversation.id, body="hi").status_code, 201)

    def test_a_message_is_saved_trimmed_and_belongs_to_the_sender(self):
        self.agree(self.client_user)
        response = self.post("conversation-messages", self.client_h, self.conversation.id, body="  Is 3pm ok?  ")
        self.assertEqual(response.status_code, 201)
        message = Message.objects.get()
        self.assertEqual((message.body, message.sender), ("Is 3pm ok?", self.client_user))
        self.assertTrue(response.json()["mine"])

    def test_empty_and_oversized_messages_are_refused(self):
        self.agree(self.client_user)
        for body in ("", "   ", None):
            self.assertEqual(self.post("conversation-messages", self.client_h, self.conversation.id, body=body).status_code, 400)
        self.assertEqual(self.post("conversation-messages", self.client_h, self.conversation.id, body="x" * 2001).status_code, 400)
        self.assertEqual(self.post("conversation-messages", self.client_h, self.conversation.id, body="x" * 2000).status_code, 201)

    def test_sending_too_fast_is_slowed_down(self):
        self.agree(self.client_user)
        codes = [self.post("conversation-messages", self.client_h, self.conversation.id, body=f"m{i}").status_code for i in range(32)]
        self.assertEqual(codes[:30], [201] * 30)
        self.assertEqual(codes[30], 429)
        cache.delete_pattern("rl:*")


class UnreadTests(ChatCase):
    def unread(self, headers):
        data = self.client.get(self.url("conversation-list"), **headers).json()
        return data["total_unread"], [c["unread_count"] for c in data["conversations"]]

    def test_unread_counts_are_per_person_and_clear_when_read(self):
        self.say(self.provider_user, "a")
        self.say(self.provider_user, "b")
        self.say(self.client_user, "mine")
        self.assertEqual(self.unread(self.client_h), (2, [2]))
        self.assertEqual(self.unread(self.provider_h), (1, [1]))
        response = self.post("conversation-read", self.client_h, self.conversation.id)
        self.assertEqual(response.json()["unread_count"], 0)
        self.assertEqual(self.unread(self.client_h), (0, [0]))
        self.assertEqual(self.unread(self.provider_h), (1, [1]))  # the provider's own count is untouched

    def test_reading_up_to_a_message_leaves_later_ones_unread_and_never_goes_backwards(self):
        first = self.say(self.provider_user, "a")
        self.say(self.provider_user, "b")
        self.post("conversation-read", self.client_h, self.conversation.id, last_id=first.id)
        self.assertEqual(self.unread(self.client_h), (1, [1]))
        self.post("conversation-read", self.client_h, self.conversation.id)
        self.post("conversation-read", self.client_h, self.conversation.id, last_id=first.id)
        self.assertEqual(self.unread(self.client_h), (0, [0]))

    def test_sending_marks_your_own_side_read_and_hidden_messages_are_not_counted(self):
        hidden = self.say(self.provider_user, "bad")
        hidden.hidden = True
        hidden.save()
        self.say(self.provider_user, "fine")
        self.assertEqual(self.unread(self.client_h), (1, [1]))
        self.agree(self.client_user)
        self.post("conversation-messages", self.client_h, self.conversation.id, body="reply")
        self.assertEqual(self.unread(self.client_h), (0, [0]))

    def test_the_list_shows_the_last_message_and_newest_chat_first(self):
        self.say(self.provider_user, "latest one")
        data = self.client.get(self.url("conversation-list"), **self.client_h).json()["conversations"][0]
        self.assertEqual(data["last_message"]["preview"], "latest one")
        self.assertEqual(data["offer_id"], self.offer.id)
        self.assertEqual(data["other_name"], "Ace Plumbing")


# ---------------------------------------------------------------------------------------------------
class BlockTests(ChatCase):
    def setUp(self):
        super().setUp()
        self.agree(self.client_user, self.provider_user)

    def send(self, headers, text="hi"):
        return self.post("conversation-messages", headers, self.conversation.id, body=text)

    def test_blocking_stops_messages_both_ways_without_telling_the_blocked_person_who_blocked(self):
        self.assertEqual(self.post("conversation-block", self.client_h, self.conversation.id).status_code, 200)
        mine = self.send(self.client_h)
        theirs = self.send(self.provider_h)
        self.assertEqual((mine.status_code, theirs.status_code), (403, 403))
        self.assertEqual(mine.json()["detail"], theirs.json()["detail"])  # same words either way
        self.assertFalse(Message.objects.exists())

    def test_the_blocker_sees_that_they_blocked_but_the_blocked_person_does_not(self):
        self.post("conversation-block", self.client_h, self.conversation.id)
        blocker = self.client.get(self.url("conversation-messages", self.conversation.id), **self.client_h).json()
        blocked = self.client.get(self.url("conversation-messages", self.conversation.id), **self.provider_h).json()
        self.assertTrue(blocker["blocked_by_me"])
        self.assertFalse(blocked["blocked_by_me"])
        self.assertFalse(blocker["can_send"])
        self.assertFalse(blocked["can_send"])

    def test_unblocking_restores_chat(self):
        self.post("conversation-block", self.client_h, self.conversation.id)
        response = self.client.delete(self.url("conversation-block", self.conversation.id), **self.client_h)
        self.assertFalse(response.json()["blocked_by_me"])
        self.assertEqual(self.send(self.provider_h).status_code, 201)

    def test_a_block_is_idempotent_and_only_affects_the_person_blocked(self):
        self.post("conversation-block", self.client_h, self.conversation.id)
        self.post("conversation-block", self.client_h, self.conversation.id)
        self.assertEqual(UserBlock.objects.count(), 1)
        block = UserBlock.objects.get()
        self.assertEqual((block.blocker, block.blocked), (self.client_user, self.provider_user))

    def test_a_blocked_person_cannot_upload_photos_or_get_a_phone_number(self):
        self.post("conversation-block", self.client_h, self.conversation.id)
        with override_settings(**R2):
            self.assertEqual(self.post("conversation-photo-upload", self.provider_h, self.conversation.id, content_type="image/jpeg").status_code, 403)
        self.assertEqual(self.client.get(self.url("conversation-call", self.conversation.id), **self.provider_h).status_code, 403)
        self.assertEqual(self.client.get(self.url("conversation-call", self.conversation.id), **self.client_h).status_code, 403)

    def test_a_blocked_person_is_not_pushed(self):
        self.post("conversation-block", self.client_h, self.conversation.id)
        with patch("messaging.push.send_to_user") as send, self.captureOnCommitCallbacks(execute=True):
            self.send(self.provider_h)
        send.assert_not_called()


# ---------------------------------------------------------------------------------------------------
class ReportTests(ChatCase):
    def test_a_message_from_the_other_person_can_be_reported_once(self):
        message = self.say(self.provider_user, "Pay me outside the app")
        response = self.post("message-report", self.client_h, self.conversation.id, message.id, reason="scam", details=" looks fake ")
        self.assertEqual(response.status_code, 201)
        self.post("message-report", self.client_h, self.conversation.id, message.id, reason="spam")
        report = MessageReport.objects.get()
        self.assertEqual((report.reason, report.details, report.reporter, report.status), ("scam", "looks fake", self.client_user, "open"))

    def test_you_cannot_report_your_own_message_or_use_a_bad_reason(self):
        mine = self.say(self.client_user, "mine")
        theirs = self.say(self.provider_user, "theirs")
        self.assertEqual(self.post("message-report", self.client_h, self.conversation.id, mine.id, reason="spam").status_code, 400)
        for reason in ("", "nope", None):
            self.assertEqual(self.post("message-report", self.client_h, self.conversation.id, theirs.id, reason=reason).status_code, 400)
        self.assertFalse(MessageReport.objects.exists())

    def test_a_message_from_another_conversation_is_not_found(self):
        other_request = ServiceRequest.objects.create(user=self.stranger_client, category="plumbing", city="Edmonton", phone="+17805550177", consent_given=True)
        other_offer = self.make_offer(ProviderProfile.objects.get(user=self.stranger_provider_user), request=other_request)
        other = Conversation.objects.create(offer=other_offer)
        foreign = self.say(self.stranger_provider_user, "x", other)
        self.assertEqual(self.post("message-report", self.client_h, self.conversation.id, foreign.id, reason="spam").status_code, 404)


# ---------------------------------------------------------------------------------------------------
class CallTests(ChatCase):
    def call(self, headers, conversation=None):
        return self.client.get(self.url("conversation-call", (conversation or self.conversation).id), **headers)

    def test_each_person_gets_the_others_number_for_the_dialer(self):
        to_provider = self.call(self.client_h).json()
        self.assertEqual((to_provider["mode"], to_provider["number"], to_provider["name"]), ("direct", "+17805550101", "Ace Plumbing"))
        to_client = self.call(self.provider_h).json()
        self.assertEqual((to_client["mode"], to_client["number"], to_client["name"]), ("direct", "+17805550199", "Pat C."))

    def test_calling_opens_only_after_the_provider_accepted(self):
        self.offer.status = LeadOffer.STATUS_DECLINED
        self.offer.save()
        for headers in (self.client_h, self.provider_h):
            response = self.call(headers)
            self.assertEqual(response.status_code, 403)
            self.assertNotIn("+1780555", response.content.decode())

    def test_strangers_get_nothing(self):
        for headers in (self.stranger_client_h, self.stranger_provider_h):
            response = self.call(headers)
            self.assertEqual(response.status_code, 404)
            self.assertNotIn("+1780555", response.content.decode())

    @override_settings(CALL_MASKING_ENABLED=True)
    def test_masked_calling_is_not_built_yet_so_the_flag_is_refused_not_ignored(self):
        response = self.call(self.client_h)
        self.assertEqual(response.status_code, 501)
        self.assertNotIn("+1780555", response.content.decode())

    def test_masking_is_off_by_default(self):
        from django.conf import settings

        self.assertFalse(settings.CALL_MASKING_ENABLED)


# ---------------------------------------------------------------------------------------------------
class DeviceTests(ChatCase):
    def test_a_phone_registers_and_a_token_moves_to_whoever_signs_in_last(self):
        self.assertEqual(self.post("device-token", self.client_h, token="tok-1", platform="android").status_code, 200)
        self.post("device-token", self.provider_h, token="tok-1")
        token = DeviceToken.objects.get()
        self.assertEqual(token.user, self.provider_user)

    def test_you_can_only_remove_your_own_token(self):
        self.post("device-token", self.client_h, token="tok-1")
        self.client.delete(self.url("device-token"), {"token": "tok-1"}, content_type="application/json", **self.provider_h)
        self.assertEqual(DeviceToken.objects.count(), 1)
        self.client.delete(self.url("device-token"), {"token": "tok-1"}, content_type="application/json", **self.client_h)
        self.assertEqual(DeviceToken.objects.count(), 0)

    def test_bad_tokens_are_refused(self):
        for token in (None, "", "   ", 5, "x" * 301):
            self.assertEqual(self.post("device-token", self.client_h, token=token).status_code, 400)
        self.assertFalse(DeviceToken.objects.exists())

    def test_it_needs_a_login(self):
        self.assertEqual(self.client.post(self.url("device-token"), {"token": "t"}, content_type="application/json", HTTP_X_API_KEY=KEY).status_code, 401)


# ---------------------------------------------------------------------------------------------------
@override_settings(**R2)
class PhotoTests(ChatCase):
    def setUp(self):
        super().setUp()
        self.agree(self.client_user, self.provider_user)

    def upload(self, headers=None, content_type="image/jpeg"):
        return self.post("conversation-photo-upload", headers or self.client_h, self.conversation.id, content_type=content_type)

    def test_the_app_gets_a_signed_upload_link_under_this_conversations_folder(self):
        with patch("messaging.storage.presign_put", return_value="https://r2.example/upload?sig=1") as presign:
            response = self.upload()
        data = response.json()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(data["key"].startswith(f"chat/{self.conversation.id}/") and data["key"].endswith(".jpg"))
        self.assertEqual(data["upload_url"], "https://r2.example/upload?sig=1")
        self.assertEqual(data["headers"], {"Content-Type": "image/jpeg"})
        self.assertEqual(data["max_bytes"], 8 * 1024 * 1024)
        presign.assert_called_once()

    def test_only_photo_types_are_accepted(self):
        for content_type in ("application/pdf", "text/html", "image/gif", "", None):
            self.assertEqual(self.upload(content_type=content_type).status_code, 400, content_type)

    @override_settings(R2_BUCKET="")
    def test_without_r2_photos_are_off_but_the_answer_is_clear(self):
        response = self.upload()
        self.assertEqual(response.status_code, 503)
        self.assertIn("Photos aren't available", response.json()["detail"])
        self.assertFalse(self.client.get(self.url("conversation-messages", self.conversation.id), **self.client_h).json()["photos_enabled"])

    def test_a_photo_message_needs_a_finished_upload_in_this_conversation(self):
        key = f"chat/{self.conversation.id}/abc.jpg"
        with patch("messaging.storage.head", return_value=None):
            self.assertEqual(self.post("conversation-messages", self.client_h, self.conversation.id, photo_key=key).status_code, 400)
        other = f"chat/{self.conversation.id + 1}/abc.jpg"
        with patch("messaging.storage.head", return_value={"size": 100, "content_type": "image/jpeg"}):
            self.assertEqual(self.post("conversation-messages", self.client_h, self.conversation.id, photo_key=other).status_code, 400)
            self.assertEqual(self.post("conversation-messages", self.client_h, self.conversation.id, photo_key="../../etc/passwd").status_code, 400)
        self.assertFalse(Message.objects.exists())

    def test_an_oversized_or_wrong_type_upload_is_refused_and_deleted(self):
        key = f"chat/{self.conversation.id}/big.jpg"
        for info in ({"size": 9 * 1024 * 1024, "content_type": "image/jpeg"}, {"size": 100, "content_type": "text/html"}):
            with patch("messaging.storage.head", return_value=info), patch("messaging.storage.delete") as delete:
                response = self.post("conversation-messages", self.client_h, self.conversation.id, photo_key=key)
            self.assertEqual(response.status_code, 400)
            delete.assert_called_once_with(key)
        self.assertFalse(Message.objects.exists())

    def test_a_good_photo_is_sent_and_only_the_two_people_get_a_signed_link_to_it(self):
        key = f"chat/{self.conversation.id}/ok.jpg"
        with patch("messaging.storage.head", return_value={"size": 1000, "content_type": "image/jpeg"}):
            response = self.post("conversation-messages", self.client_h, self.conversation.id, photo_key=key, body="the leak")
        self.assertEqual(response.status_code, 201)
        message = Message.objects.get()
        self.assertEqual((message.photo_key, message.body), (key, "the leak"))
        with patch("messaging.storage.presign_get", return_value="https://r2.example/view?sig=2"):
            for headers in (self.client_h, self.provider_h):
                data = self.client.get(self.url("conversation-messages", self.conversation.id), **headers).json()
                self.assertEqual(data["messages"][0]["photo_url"], "https://r2.example/view?sig=2")
            stranger = self.client.get(self.url("conversation-messages", self.conversation.id), **self.stranger_client_h)
            self.assertEqual(stranger.status_code, 404)
            self.assertNotIn("r2.example", stranger.content.decode())

    def test_a_hidden_photo_is_never_linked(self):
        message = Message.objects.create(conversation=self.conversation, sender=self.provider_user, photo_key=f"chat/{self.conversation.id}/x.jpg", hidden=True)
        with patch("messaging.storage.presign_get", return_value="https://r2.example/view") as presign:
            data = self.client.get(self.url("conversation-messages", self.conversation.id), **self.client_h).json()
        self.assertIsNone(data["messages"][0]["photo_url"])
        presign.assert_not_called()
        self.assertTrue(message.hidden)

    def test_the_real_signed_links_are_private_and_expire(self):
        put = storage.presign_put("chat/1/a.jpg", "image/jpeg")
        get = storage.presign_get("chat/1/a.jpg")
        for url in (put, get):
            self.assertIn("acct123.r2.cloudflarestorage.com/chat-bucket/chat/1/a.jpg", url)
            self.assertIn("X-Amz-Signature=", url)
            self.assertIn("X-Amz-Expires=", url)
            self.assertNotIn("shh-secret", url)  # the secret never appears in a link
        self.assertIn("X-Amz-Expires=600", put)
        self.assertIn("X-Amz-Expires=900", get)

    def test_head_reports_a_missing_object_as_none_and_other_errors_as_errors(self):
        client = MagicMock()
        client.head_object.side_effect = ClientError({"Error": {"Code": "404"}}, "HeadObject")
        with patch("messaging.storage._client", return_value=client):
            self.assertIsNone(storage.head("chat/1/none.jpg"))
        client.head_object.side_effect = ClientError({"Error": {"Code": "403"}}, "HeadObject")
        with patch("messaging.storage._client", return_value=client), self.assertRaises(ClientError):
            storage.head("chat/1/denied.jpg")


# ---------------------------------------------------------------------------------------------------
class PushTests(ChatCase):
    def setUp(self):
        super().setUp()
        self.agree(self.client_user, self.provider_user)
        DeviceToken.objects.create(user=self.provider_user, token="provider-phone")

    def send(self, text="Secret details"):
        with self.captureOnCommitCallbacks(execute=True):
            return self.post("conversation-messages", self.client_h, self.conversation.id, body=text)

    @override_settings(FCM_SERVICE_ACCOUNT_JSON=FAKE_FCM)
    def test_the_other_person_is_pushed_a_generic_message_never_the_text(self):
        response = MagicMock(status_code=200)
        with patch("messaging.push._project_id_and_token", return_value=("demo-proj", "access-token")), \
                patch("messaging.push.requests.post", return_value=response) as post:
            self.assertEqual(self.send("Secret details about my address").status_code, 201)
        post.assert_called_once()
        url = post.call_args.args[0]
        sent = post.call_args.kwargs["json"]["message"]
        self.assertEqual(url, "https://fcm.googleapis.com/v1/projects/demo-proj/messages:send")
        self.assertEqual(sent["token"], "provider-phone")
        self.assertEqual(sent["notification"], {"title": "New message", "body": "Pat C. sent you a message."})
        self.assertEqual(sent["data"], {"type": "chat", "conversation_id": str(self.conversation.id)})
        self.assertNotIn("Secret details", json.dumps(sent))
        self.assertEqual(post.call_args.kwargs["headers"]["Authorization"], "Bearer access-token")

    def test_without_firebase_configured_nothing_is_sent_and_chat_still_works(self):
        with patch("messaging.push.requests.post") as post:
            self.assertEqual(self.send().status_code, 201)
        post.assert_not_called()

    @override_settings(FCM_SERVICE_ACCOUNT_JSON=FAKE_FCM)
    def test_a_push_failure_never_breaks_sending(self):
        with patch("messaging.push._project_id_and_token", side_effect=RuntimeError("firebase down")):
            self.assertEqual(self.send().status_code, 201)
        with patch("messaging.push._project_id_and_token", return_value=("demo-proj", "t")), \
                patch("messaging.push.requests.post", side_effect=OSError("network down")):
            self.assertEqual(self.send("again").status_code, 201)
        self.assertEqual(Message.objects.count(), 2)

    @override_settings(FCM_SERVICE_ACCOUNT_JSON=FAKE_FCM)
    def test_a_token_firebase_says_is_gone_is_forgotten(self):
        gone = MagicMock(status_code=404)
        gone.json.return_value = {"error": {"status": "NOT_FOUND"}}
        with patch("messaging.push._project_id_and_token", return_value=("demo-proj", "t")), \
                patch("messaging.push.requests.post", return_value=gone):
            self.send()
        self.assertFalse(DeviceToken.objects.exists())

    @override_settings(FCM_SERVICE_ACCOUNT_JSON=FAKE_FCM)
    def test_other_errors_keep_the_token_for_next_time(self):
        broken = MagicMock(status_code=500)
        broken.json.return_value = {"error": {"status": "INTERNAL"}}
        with patch("messaging.push._project_id_and_token", return_value=("demo-proj", "t")), \
                patch("messaging.push.requests.post", return_value=broken):
            self.assertEqual(self.send().status_code, 201)
        self.assertEqual(DeviceToken.objects.count(), 1)

    @override_settings(FCM_SERVICE_ACCOUNT_JSON=FAKE_FCM)
    def test_the_sender_is_not_pushed_about_their_own_message(self):
        DeviceToken.objects.create(user=self.client_user, token="client-phone")
        with patch("messaging.push._project_id_and_token", return_value=("demo-proj", "t")), \
                patch("messaging.push.requests.post", return_value=MagicMock(status_code=200)) as post:
            self.send()
        tokens = [call.kwargs["json"]["message"]["token"] for call in post.call_args_list]
        self.assertEqual(tokens, ["provider-phone"])


# ---------------------------------------------------------------------------------------------------
class AdminModerationTests(ChatCase):
    def setUp(self):
        super().setUp()
        self.staff = User.objects.create_superuser("boss", "boss@example.com", "pw-for-tests-123")
        self.client.force_login(self.staff)
        self.message = self.say(self.provider_user, "Send money to this account")
        self.report = MessageReport.objects.create(message=self.message, reporter=self.client_user, reason="scam")

    def act(self, action, report=None):
        return self.client.post(
            "/admin/messaging/messagereport/", {"action": action, "_selected_action": [(report or self.report).pk]}, follow=True
        )

    def test_the_moderation_pages_open(self):
        for path in ("messagereport", "message", "conversation", "userblock", "chattermsacceptance", "devicetoken"):
            self.assertEqual(self.client.get(f"/admin/messaging/{path}/").status_code, 200, path)
        self.assertEqual(self.client.get(f"/admin/messaging/messagereport/{self.report.pk}/change/").status_code, 200)
        self.assertEqual(self.client.get(f"/admin/messaging/conversation/{self.conversation.pk}/change/").status_code, 200)

    def test_hiding_the_reported_message_removes_it_for_everyone_and_closes_the_report(self):
        self.act("hide_message")
        self.message.refresh_from_db()
        self.report.refresh_from_db()
        self.assertTrue(self.message.hidden)
        self.assertEqual(self.report.status, MessageReport.STATUS_ACTIONED)
        self.assertIsNotNone(self.report.reviewed_at)
        data = self.client.get(self.url("conversation-messages", self.conversation.id), **self.client_h).json()
        self.assertTrue(data["messages"][0]["removed"])

    def test_suspending_the_sender_locks_them_out_and_hides_the_message(self):
        self.act("suspend_sender")
        self.provider_user.refresh_from_db()
        self.assertFalse(self.provider_user.is_active)
        self.message.refresh_from_db()
        self.assertTrue(self.message.hidden)
        self.agree(self.provider_user)
        # Their token no longer works at all.
        self.assertEqual(self.post("conversation-messages", self.provider_h, self.conversation.id, body="hi").status_code, 401)

    def test_staff_accounts_are_never_suspended_from_a_report(self):
        staff_message = Message.objects.create(conversation=self.conversation, sender=self.staff, body="x")
        report = MessageReport.objects.create(message=staff_message, reporter=self.client_user, reason="spam")
        self.act("suspend_sender", report)
        self.staff.refresh_from_db()
        self.assertTrue(self.staff.is_active)

    def test_dismissing_closes_the_report_and_leaves_the_message(self):
        self.act("dismiss")
        self.report.refresh_from_db()
        self.message.refresh_from_db()
        self.assertEqual(self.report.status, MessageReport.STATUS_DISMISSED)
        self.assertFalse(self.message.hidden)

    def test_messages_can_be_hidden_and_restored_from_the_message_list(self):
        self.client.post("/admin/messaging/message/", {"action": "hide_selected", "_selected_action": [self.message.pk]})
        self.message.refresh_from_db()
        self.assertTrue(self.message.hidden)
        self.client.post("/admin/messaging/message/", {"action": "restore_selected", "_selected_action": [self.message.pk]})
        self.message.refresh_from_db()
        self.assertFalse(self.message.hidden)

    def test_admin_cannot_write_into_a_conversation(self):
        self.assertEqual(self.client.get("/admin/messaging/conversation/add/").status_code, 403)
        self.assertEqual(self.client.get("/admin/messaging/message/add/").status_code, 403)

    def test_a_normal_user_cannot_open_the_moderation_pages(self):
        self.client.logout()
        self.client.force_login(self.client_user)
        self.assertEqual(self.client.get("/admin/messaging/messagereport/").status_code, 302)  # sent to the admin login


# ---------------------------------------------------------------------------------------------------
class ConfigCommandTests(TestCase):
    def run_command(self, *args):
        out = StringIO()
        call_command("check_messaging_config", *args, stdout=out)
        return out.getvalue()

    def test_nothing_set_says_so(self):
        text = self.run_command()
        self.assertIn("FCM_SERVICE_ACCOUNT_JSON is not set", text)
        self.assertIn("R2_ACCOUNT_ID", text)

    @override_settings(FCM_SERVICE_ACCOUNT_JSON=FAKE_FCM, **R2)
    def test_when_set_it_confirms_but_never_prints_a_secret(self):
        text = self.run_command()
        self.assertIn("demo-proj", text)
        self.assertIn("chat-bucket", text)
        for secret in ("PRIVATE-KEY-MUST-NEVER-BE-PRINTED", "shh-secret", "AKIAFAKE", "svc@demo-proj"):
            self.assertNotIn(secret, text)

    @override_settings(FCM_SERVICE_ACCOUNT_JSON="{not json")
    def test_bad_json_is_reported_without_echoing_it(self):
        text = self.run_command()
        self.assertIn("not valid JSON", text)
        self.assertNotIn("{not json", text)

    @override_settings(FCM_SERVICE_ACCOUNT_JSON=json.dumps({"project_id": "p"}))
    def test_missing_fields_are_named(self):
        self.assertIn("missing: client_email, private_key", self.run_command())

    @override_settings(FCM_SERVICE_ACCOUNT_JSON=FAKE_FCM, **R2)
    def test_live_mode_reports_a_failed_connection_without_secrets(self):
        with patch("messaging.push._project_id_and_token", side_effect=RuntimeError("nope")), \
                patch("messaging.storage._client", side_effect=RuntimeError("nope")):
            text = self.run_command("--live")
        self.assertIn("could not get a token", text)
        self.assertIn("could not reach it", text)
        self.assertNotIn("shh-secret", text)
