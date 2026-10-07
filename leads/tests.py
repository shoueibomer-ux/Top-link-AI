import re
from datetime import datetime, timedelta, timezone as dt_timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

from django.contrib.auth import get_user_model
from django.core import mail
from django.core.management import call_command
from django.test import TestCase, override_settings
from django.utils import timezone
from twilio.base.exceptions import TwilioRestException
from twilio.request_validator import RequestValidator

from catalog.models import Service
from provider_search.models import ServiceRequest

from . import jobs, services, sms
from .models import DailySummaryLog, LeadOffer, Provider
from .phone import normalize_north_american_phone, normalize_phone

TOKEN = "test-auth-token"
SMS_ON = dict(
    SMS_ENABLED=True,
    TWILIO_ACCOUNT_SID="ACtest",
    TWILIO_AUTH_TOKEN=TOKEN,
    TWILIO_FROM_NUMBER="+18005550000",
)
CLIENT_PHONE = "+17805550199"
WEBHOOK_URL = "http://testserver/api/twilio/sms/"


class TwilioMocked(TestCase):
    """Every test in the leads app runs with Twilio mocked out: nothing here can
    reach the network, and self.twilio records every message that would be sent."""

    def setUp(self):
        patcher = patch("leads.sms._client")
        self.addCleanup(patcher.stop)
        self.twilio = patcher.start().return_value
        self.twilio.messages.create.return_value = MagicMock(sid="SM-fake")

    @property
    def sent(self):
        return [call.kwargs for call in self.twilio.messages.create.call_args_list]


def make_request(category="plumbing", city="Edmonton", urgency="today", description="Leaking kitchen sink", **kw):
    return ServiceRequest.objects.create(
        device_id="dev-1", category=category, city=city, phone=CLIENT_PHONE, consent_given=True,
        urgency=urgency, problem_description=description, **kw,
    )


def make_provider(name="Ace Plumbing", phone="780 555 0101", services_=("plumbing",), areas=("Edmonton",), **kw):
    kw.setdefault("sms_consent_confirmed", True)
    provider = Provider.objects.create(business_name=name, phone=phone, service_areas=list(areas), **kw)
    provider.services.set(Service.objects.filter(slug__in=services_))
    return provider


def make_offer(request=None, provider=None, sent_minutes_ago=None, **kw):
    request = request or make_request()
    provider = provider or make_provider()
    offer = LeadOffer.objects.create(service_request=request, provider=provider, **kw)
    if sent_minutes_ago is not None:
        offer.mark_sent(now=timezone.now() - timedelta(minutes=sent_minutes_ago))
    return offer


# ---------------------------------------------------------------------------
class PhoneTests(TestCase):
    def test_north_american_numbers_become_e164(self):
        for raw in ("780 555 0100", "(780) 555-0100", "780.555.0100", "1-780-555-0100", "+1 780 555 0100"):
            self.assertEqual(normalize_phone(raw), "+17805550100", raw)

    def test_garbage_is_rejected(self):
        for raw in ("", "abc", "555-0100", "12345"):
            self.assertEqual(normalize_phone(raw), "", raw)


class NorthAmericanPhoneTests(TestCase):
    def test_every_common_way_of_writing_a_number_becomes_e164(self):
        for raw in ("780 555 0100", "(780) 555-0100", "780.555.0100", "780-555-0100", "1-780-555-0100",
                    "17805550100", "+1 780 555 0100", "+1 (780) 555-0100", "+17805550100", "  7805550100 "):
            self.assertEqual(normalize_north_american_phone(raw), "+17805550100", raw)

    def test_eleven_digits_must_start_with_1(self):
        self.assertEqual(normalize_north_american_phone("58792199587"), "")
        self.assertEqual(normalize_north_american_phone("15872199587"), "+15872199587")

    def test_what_is_not_a_north_american_number_is_rejected(self):
        for raw in ("", "   ", "abc", "555 0100", "780555010", "178055501001", "+44 20 7946 0958", "+380 44 123 4567",
                    "1234567890", "0805550100", "7801550100", "780-555-CALL", "780 555 0100 ext 5", "++17805550100",
                    "780+5550100", "7805550100+", "()-."):
            self.assertEqual(normalize_north_american_phone(raw), "", raw)

    def test_non_strings_are_rejected(self):
        for value in (None, 7805550100, ["7805550100"], True):
            self.assertEqual(normalize_north_american_phone(value), "")

    def test_provider_phones_still_accept_other_formats_through_the_looser_helper(self):
        self.assertEqual(normalize_phone("+44 20 7946 0958"), "+442079460958")


class ProviderTests(TestCase):
    def test_the_phone_is_stored_normalised_so_an_inbound_sms_can_match_it(self):
        self.assertEqual(make_provider(phone="(780) 555-0101").phone, "+17805550101")

    def test_an_unreadable_phone_fails_validation(self):
        from django.core.exceptions import ValidationError

        with self.assertRaises(ValidationError):
            Provider(business_name="x", phone="nope").full_clean()

    def test_who_can_be_texted(self):
        self.assertTrue(make_provider().can_text)
        self.assertEqual(make_provider("a", "780 555 0102", sms_opt_out=True).cannot_text_reason, "opted out (STOP)")
        self.assertEqual(
            make_provider("b", "780 555 0103", sms_consent_confirmed=False).cannot_text_reason, "no SMS consent recorded"
        )
        self.assertEqual(make_provider("c", "780 555 0104", is_active=False).cannot_text_reason, "inactive")


class LeadOfferModelTests(TestCase):
    def test_a_yes_records_the_reply_time_from_when_it_was_sent(self):
        offer = make_offer()
        sent = datetime(2026, 10, 7, 15, 0, tzinfo=dt_timezone.utc)
        offer.mark_sent(now=sent)
        self.assertTrue(offer.record_reply(LeadOffer.REPLY_YES, LeadOffer.CHANNEL_MANUAL, now=sent + timedelta(minutes=12)))
        offer.refresh_from_db()
        self.assertEqual(offer.status, LeadOffer.STATUS_ACCEPTED)
        self.assertEqual(offer.response_time, timedelta(minutes=12))
        self.assertEqual(offer.responded_at, sent + timedelta(minutes=12))
        self.assertEqual(offer.reply_channel, "manual")

    def test_a_no_is_declined_with_a_response_time(self):
        offer = make_offer(sent_minutes_ago=5)
        offer.record_reply(LeadOffer.REPLY_NO, LeadOffer.CHANNEL_SMS)
        self.assertEqual(offer.status, LeadOffer.STATUS_DECLINED)
        self.assertIsNotNone(offer.response_time)

    def test_no_answer_expires_the_offer_without_a_response_time(self):
        offer = make_offer(sent_minutes_ago=60)
        offer.record_reply(LeadOffer.REPLY_NO_ANSWER, LeadOffer.CHANNEL_MANUAL)
        self.assertEqual(offer.status, LeadOffer.STATUS_EXPIRED)
        self.assertIsNone(offer.response_time)
        self.assertIsNone(offer.responded_at)

    def test_a_late_yes_after_no_answer_is_still_recorded(self):
        offer = make_offer(sent_minutes_ago=60)
        offer.record_reply(LeadOffer.REPLY_NO_ANSWER, LeadOffer.CHANNEL_MANUAL)
        self.assertTrue(offer.record_reply(LeadOffer.REPLY_YES, LeadOffer.CHANNEL_MANUAL))
        self.assertEqual(offer.status, LeadOffer.STATUS_ACCEPTED)

    def test_nothing_is_recorded_for_an_offer_that_was_never_sent(self):
        offer = make_offer()
        self.assertFalse(offer.record_reply(LeadOffer.REPLY_YES, LeadOffer.CHANNEL_MANUAL))
        self.assertEqual(offer.status, LeadOffer.STATUS_PENDING)

    def test_a_second_yes_or_no_does_not_overwrite_the_first(self):
        offer = make_offer(sent_minutes_ago=5)
        offer.record_reply(LeadOffer.REPLY_YES, LeadOffer.CHANNEL_SMS)
        first = offer.responded_at
        self.assertFalse(offer.record_reply(LeadOffer.REPLY_NO, LeadOffer.CHANNEL_SMS))
        self.assertEqual((offer.status, offer.responded_at), (LeadOffer.STATUS_ACCEPTED, first))

    def test_one_offer_per_request_and_provider(self):
        from django.db import IntegrityError, transaction

        offer = make_offer()
        with self.assertRaises(IntegrityError), transaction.atomic():
            LeadOffer.objects.create(service_request=offer.service_request, provider=offer.provider)

    def test_ticking_hired_stamps_when_and_unticking_clears_it(self):
        offer = make_offer()
        offer.hired = True
        offer.save()
        offer.refresh_from_db()
        self.assertIsNotNone(offer.hired_at)
        offer.hired = False
        offer.save()
        offer.refresh_from_db()
        self.assertIsNone(offer.hired_at)


# ---------------------------------------------------------------------------
class MatchingTests(TestCase):
    def test_providers_for_the_service_and_city_are_suggested(self):
        match = make_provider("Match")
        make_provider("Wrong service", "780 555 0102", services_=("electrical",))
        make_provider("Wrong city", "780 555 0103", areas=("Calgary",))
        names = [c.provider.business_name for c in services.suggest_providers(make_request())]
        self.assertEqual(names, [match.business_name])

    def test_a_provider_with_no_service_area_is_included_and_flagged(self):
        make_provider("Anywhere", areas=())
        (candidate,) = services.suggest_providers(make_request())
        self.assertEqual(candidate.area_note, "no service area set")

    def test_providers_who_cant_be_texted_are_shown_last_with_the_reason(self):
        make_provider("Opted out", "780 555 0102", sms_opt_out=True)
        make_provider("Fine", "780 555 0103")
        candidates = services.suggest_providers(make_request())
        self.assertEqual([c.provider.business_name for c in candidates], ["Fine", "Opted out"])
        self.assertEqual(candidates[1].reason, "opted out (STOP)")

    def test_providers_who_said_yes_before_rank_first(self):
        slow = make_provider("Slow", "780 555 0102")
        keen = make_provider("Keen", "780 555 0103")
        make_offer(provider=keen, sent_minutes_ago=10).record_reply(LeadOffer.REPLY_YES, LeadOffer.CHANNEL_SMS)
        names = [c.provider.business_name for c in services.suggest_providers(make_request())]
        self.assertEqual(names, ["Keen", "Slow"])
        self.assertTrue(slow)

    def test_a_provider_already_offered_this_request_is_marked(self):
        request = make_request()
        provider = make_provider()
        make_offer(request, provider)
        (candidate,) = services.suggest_providers(request)
        self.assertTrue(candidate.already_offered)

    def test_waitlisted_requests_are_not_forwardable_until_the_service_launches(self):
        request = make_request(category="lawn-care", status=ServiceRequest.STATUS_WAITLISTED)
        self.assertIn("isn't launched", services.forwarding_problem(request))
        Service.objects.filter(slug="lawn-care").update(is_launched=True)
        self.assertEqual(services.forwarding_problem(request), "")

    def test_a_request_without_consent_is_not_forwardable(self):
        request = make_request(consent_given=False) if False else make_request()
        ServiceRequest.objects.filter(pk=request.pk).update(consent_given=False)
        request.refresh_from_db()
        self.assertIn("consent", services.forwarding_problem(request))


class CreateOffersTests(TwilioMocked):
    def test_offers_are_created_pending_and_nothing_is_sent(self):
        request = make_request()
        offers = services.create_offers(request, [make_provider("A"), make_provider("B", "780 555 0102")])
        self.assertEqual([o.status for o in offers], [LeadOffer.STATUS_PENDING] * 2)
        self.assertEqual(self.sent, [])

    def test_at_most_three_providers(self):
        providers = [make_provider(f"P{i}", f"780 555 01{i:02d}") for i in range(4)]
        with self.assertRaisesMessage(ValueError, "at most 3"):
            services.create_offers(make_request(), providers)
        self.assertEqual(LeadOffer.objects.count(), 0)

    def test_at_least_one_provider(self):
        with self.assertRaises(ValueError):
            services.create_offers(make_request(), [])

    def test_a_provider_who_opted_out_is_refused_and_nothing_at_all_is_created(self):
        good = make_provider("Good")
        bad = make_provider("Bad", "780 555 0102", sms_opt_out=True)
        with self.assertRaisesMessage(ValueError, "opted out"):
            services.create_offers(make_request(), [good, bad])
        self.assertEqual(LeadOffer.objects.count(), 0)

    def test_a_provider_without_recorded_consent_is_refused(self):
        with self.assertRaisesMessage(ValueError, "consent"):
            services.create_offers(make_request(), [make_provider(sms_consent_confirmed=False)])

    def test_no_duplicate_offer_for_the_same_request(self):
        request, provider = make_request(), make_provider()
        services.create_offers(request, [provider])
        with self.assertRaisesMessage(ValueError, "already has an offer"):
            services.create_offers(request, [provider])

    def test_an_unlaunched_service_is_refused(self):
        request = make_request(category="lawn-care", status=ServiceRequest.STATUS_WAITLISTED)
        with self.assertRaisesMessage(ValueError, "isn't launched"):
            services.create_offers(request, [make_provider(services_=("lawn-care",))])


class MessageTests(TestCase):
    def setUp(self):
        self.offer = make_offer()

    def test_the_first_text_identifies_us_summarises_the_request_and_asks_for_yes_or_no(self):
        text = services.offer_message(self.offer)
        self.assertTrue(text.startswith("Top-Link AI"))
        self.assertIn("Plumbing", text)
        self.assertIn("Edmonton", text)
        self.assertIn("needed today", text)
        self.assertIn(f"YES {self.offer.ref}", text)
        self.assertIn(f"NO {self.offer.ref}", text)
        self.assertIn("STOP", text)

    def test_the_first_text_never_contains_the_clients_phone_or_free_text(self):
        text = services.offer_message(self.offer)
        self.assertNotIn(CLIENT_PHONE, text)
        self.assertNotIn("780", text)
        self.assertNotIn("0199", text)
        self.assertNotIn("Leaking kitchen sink", text)

    def test_the_second_text_carries_the_clients_phone_and_notes(self):
        text = services.followup_message(self.offer)
        self.assertIn(CLIENT_PHONE, text)
        self.assertIn("Leaking kitchen sink", text)

    def test_urgency_wording(self):
        request = make_request(urgency="")
        self.assertIn("urgency not specified", services.offer_message(make_offer(request, make_provider("x", "780 555 0150"))))

    def test_the_manual_links_carry_the_message(self):
        link = services.sms_link("+17805550101", "Hello there")
        self.assertTrue(link.startswith("sms:+17805550101?"))
        self.assertIn("Hello%20there", link)
        self.assertEqual(services.tel_link("+17805550101"), "tel:+17805550101")


# ---------------------------------------------------------------------------
class SmsWrapperTests(TwilioMocked):
    def test_it_refuses_to_send_when_sms_is_off(self):
        with self.assertRaisesMessage(sms.SmsError, "turned off"):
            sms.send_sms("+17805550101", "hi")
        self.assertEqual(self.sent, [])

    @override_settings(SMS_ENABLED=True, TWILIO_ACCOUNT_SID="", TWILIO_AUTH_TOKEN="", TWILIO_FROM_NUMBER="")
    def test_it_refuses_to_send_without_twilio_settings(self):
        with self.assertRaisesMessage(sms.SmsError, "not configured"):
            sms.send_sms("+17805550101", "hi")
        self.assertEqual(self.sent, [])

    @override_settings(**SMS_ON)
    def test_it_sends_from_the_configured_number_and_returns_the_message_id(self):
        self.assertEqual(sms.send_sms("+17805550101", "hi"), "SM-fake")
        self.assertEqual(self.sent, [{"to": "+17805550101", "from_": "+18005550000", "body": "hi"}])

    @override_settings(**SMS_ON)
    def test_a_twilio_error_becomes_an_sms_error(self):
        self.twilio.messages.create.side_effect = TwilioRestException(400, "/x", "Bad number", code=21211)
        with self.assertRaises(sms.SmsError) as caught:
            sms.send_sms("+1", "hi")
        self.assertEqual(caught.exception.code, 21211)
        self.assertNotIsInstance(caught.exception, sms.SmsOptedOut)

    @override_settings(**SMS_ON)
    def test_a_stop_block_becomes_opted_out(self):
        self.twilio.messages.create.side_effect = TwilioRestException(400, "/x", "Blocked", code=21610)
        with self.assertRaises(sms.SmsOptedOut):
            sms.send_sms("+17805550101", "hi")

    def test_twilio_settings_come_from_the_environment_and_default_to_off(self):
        from django.conf import settings

        self.assertFalse(settings.SMS_ENABLED)
        for name in ("TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_FROM_NUMBER"):
            self.assertEqual(getattr(settings, name), "", name)

    def test_no_twilio_credentials_are_hardcoded_in_the_source(self):
        pattern = re.compile(r"\bAC[0-9a-f]{32}\b|\b[0-9a-f]{32}\b")
        for path in Path(__file__).parent.rglob("*.py"):
            if "migrations" in path.parts or path.name == "tests.py":
                continue
            self.assertIsNone(pattern.search(path.read_text(encoding="utf-8")), path.name)


# ---------------------------------------------------------------------------
class AdminFlowBase(TwilioMocked):
    def setUp(self):
        super().setUp()
        self.admin_user = get_user_model().objects.create_superuser("boss", "boss@example.com", "pw-for-tests-123")
        self.client.force_login(self.admin_user)
        self.request_obj = make_request()
        self.a = make_provider("Ace Plumbing", "780 555 0101")
        self.b = make_provider("Best Pipes", "780 555 0102")
        self.c = make_provider("Cool Drains", "780 555 0103")
        self.d = make_provider("Dan's Plumbing", "780 555 0104")
        self.send_url = f"/admin/leads/leadoffer/send/{self.request_obj.pk}/"
        self.tracker_url = f"/admin/leads/leadoffer/tracker/{self.request_obj.pk}/"

    def post_providers(self, *providers, follow=False):
        return self.client.post(self.send_url, {"providers": [p.pk for p in providers]}, follow=follow)


class SendToProvidersActionTests(AdminFlowBase):
    ACTION_URL = "/admin/provider_search/servicerequest/"

    def run_action(self, *pks):
        return self.client.post(
            self.ACTION_URL, {"action": "send_to_providers", "_selected_action": [str(p) for p in pks]}
        )

    def test_the_action_opens_the_provider_page_for_one_request(self):
        response = self.run_action(self.request_obj.pk)
        self.assertRedirects(response, self.send_url, fetch_redirect_response=False)
        self.assertEqual(self.sent, [])

    def test_selecting_several_requests_is_refused(self):
        other = make_request()
        response = self.run_action(self.request_obj.pk, other.pk)
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], self.ACTION_URL)
        self.assertEqual(LeadOffer.objects.count(), 0)

    def test_the_request_list_offers_the_action_and_shows_offer_counts(self):
        make_offer(self.request_obj, self.a)
        page = self.client.get(self.ACTION_URL)
        self.assertContains(page, "Send to providers...")
        self.assertContains(page, "1 offer")


class SendPageTests(AdminFlowBase):
    def test_get_lists_matching_providers_and_creates_nothing(self):
        page = self.client.get(self.send_url)
        self.assertEqual(page.status_code, 200)
        for provider in (self.a, self.b, self.c, self.d):
            self.assertContains(page, provider.business_name.replace("'", "&#x27;"))
        self.assertEqual(LeadOffer.objects.count(), 0)
        self.assertEqual(self.sent, [])

    @override_settings(**SMS_ON)
    def test_get_never_sends_even_with_sms_on(self):
        self.client.get(self.send_url)
        self.assertEqual(self.sent, [])
        self.assertEqual(LeadOffer.objects.count(), 0)

    def test_the_page_says_when_sms_is_off(self):
        self.assertContains(self.client.get(self.send_url), "SMS is off")

    def test_an_unlaunched_request_shows_why_it_cannot_be_forwarded(self):
        request = make_request(category="lawn-care", status=ServiceRequest.STATUS_WAITLISTED)
        page = self.client.get(f"/admin/leads/leadoffer/send/{request.pk}/")
        self.assertContains(page, "isn&#x27;t launched yet")
        self.client.post(f"/admin/leads/leadoffer/send/{request.pk}/", {"providers": [self.a.pk]})
        self.assertEqual(LeadOffer.objects.count(), 0)

    def test_it_needs_a_staff_login(self):
        self.client.logout()
        self.assertEqual(self.client.get(self.send_url).status_code, 302)
        self.assertEqual(self.post_providers(self.a).status_code, 302)
        self.assertEqual(LeadOffer.objects.count(), 0)


class ManualModeTests(AdminFlowBase):
    """SMS_ENABLED is off: offers are created and messages shown to copy; nothing is sent."""

    def test_posting_creates_pending_offers_and_sends_nothing(self):
        response = self.post_providers(self.a, self.b)
        self.assertRedirects(response, self.tracker_url, fetch_redirect_response=False)
        offers = LeadOffer.objects.all()
        self.assertEqual(offers.count(), 2)
        self.assertEqual({o.status for o in offers}, {LeadOffer.STATUS_PENDING})
        self.assertEqual({o.sent_at for o in offers}, {None})
        self.assertEqual(self.sent, [])

    def test_the_tracker_shows_a_ready_to_copy_message_with_sms_and_call_links(self):
        self.post_providers(self.a)
        offer = LeadOffer.objects.get()
        page = self.client.get(self.tracker_url)
        self.assertContains(page, "Copy message")
        self.assertContains(page, "Top-Link AI: new client request.")
        self.assertContains(page, f"YES {offer.ref}")
        self.assertContains(page, "sms:+17805550101?")
        self.assertContains(page, "tel:+17805550101")
        self.assertContains(page, "Mark as sent")
        self.assertNotContains(page, "Send SMS now")

    def test_more_than_three_providers_is_refused_with_nothing_created(self):
        response = self.post_providers(self.a, self.b, self.c, self.d, follow=True)
        self.assertContains(response, "at most 3")
        self.assertEqual(LeadOffer.objects.count(), 0)

    def test_posting_with_nobody_selected_is_refused(self):
        response = self.client.post(self.send_url, {}, follow=True)
        self.assertContains(response, "at least one provider")
        self.assertEqual(LeadOffer.objects.count(), 0)

    def test_an_opted_out_provider_cannot_be_picked_even_with_a_crafted_post(self):
        Provider.objects.filter(pk=self.b.pk).update(sms_opt_out=True)
        response = self.post_providers(self.a, self.b, follow=True)
        self.assertContains(response, "opted out")
        self.assertEqual(LeadOffer.objects.count(), 0)

    def act(self, offer, action):
        return self.client.post(f"/admin/leads/leadoffer/{offer.pk}/act/", {"action": action}, follow=True)

    def test_mark_sent_starts_the_response_clock(self):
        self.post_providers(self.a)
        offer = LeadOffer.objects.get()
        before = timezone.now()
        self.act(offer, "mark_sent")
        offer.refresh_from_db()
        self.assertEqual(offer.status, LeadOffer.STATUS_SENT)
        self.assertGreaterEqual(offer.sent_at, before)

    def test_recording_yes_computes_the_response_time_from_when_it_was_marked_sent(self):
        offer = make_offer(self.request_obj, self.a, sent_minutes_ago=15)
        self.act(offer, "yes")
        offer.refresh_from_db()
        self.assertEqual(offer.status, LeadOffer.STATUS_ACCEPTED)
        self.assertEqual(offer.reply_channel, "manual")
        self.assertAlmostEqual(offer.response_time.total_seconds(), 15 * 60, delta=30)

    def test_recording_no_and_no_answer(self):
        declined = make_offer(self.request_obj, self.a, sent_minutes_ago=5)
        silent = make_offer(self.request_obj, self.b, sent_minutes_ago=5)
        self.act(declined, "no")
        self.act(silent, "no_answer")
        declined.refresh_from_db()
        silent.refresh_from_db()
        self.assertEqual(declined.status, LeadOffer.STATUS_DECLINED)
        self.assertIsNotNone(declined.response_time)
        self.assertEqual(silent.status, LeadOffer.STATUS_EXPIRED)
        self.assertIsNone(silent.response_time)

    def test_a_reply_cannot_be_recorded_before_the_offer_is_marked_sent(self):
        offer = make_offer(self.request_obj, self.a)
        response = self.act(offer, "yes")
        self.assertContains(response, "not sent yet")
        offer.refresh_from_db()
        self.assertEqual(offer.status, LeadOffer.STATUS_PENDING)

    def test_after_a_yes_the_tracker_offers_the_client_phone_message_to_send_by_hand(self):
        offer = make_offer(self.request_obj, self.a, sent_minutes_ago=5)
        self.act(offer, "yes")
        page = self.client.get(self.tracker_url)
        self.assertContains(page, f"Client phone: {CLIENT_PHONE}")
        self.act(offer, "followup_sent")
        offer.refresh_from_db()
        self.assertIsNotNone(offer.client_phone_shared_at)
        self.assertNotContains(self.client.get(self.tracker_url), "Mark as shared")

    def test_the_buttons_need_post_and_a_staff_login(self):
        offer = make_offer(self.request_obj, self.a, sent_minutes_ago=5)
        self.client.get(f"/admin/leads/leadoffer/{offer.pk}/act/")
        offer.refresh_from_db()
        self.assertEqual(offer.status, LeadOffer.STATUS_SENT)
        self.client.logout()
        self.client.post(f"/admin/leads/leadoffer/{offer.pk}/act/", {"action": "yes"})
        offer.refresh_from_db()
        self.assertEqual(offer.status, LeadOffer.STATUS_SENT)

    def test_hired_and_job_completed_are_editable_in_the_offer_list(self):
        response = self.client.get("/admin/leads/leadoffer/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(set(response.context_data["cl"].list_editable), {"hired", "job_completed"})

    def test_offers_cannot_be_added_by_hand_around_the_rules(self):
        self.assertEqual(self.client.get("/admin/leads/leadoffer/add/").status_code, 403)

    def test_providers_can_be_added_in_the_admin(self):
        response = self.client.post("/admin/leads/provider/add/", {
            "business_name": "New Co", "contact_name": "Pat", "phone": "(780) 555 0177",
            "services": [Service.objects.get(slug="plumbing").pk], "service_areas": ["Edmonton", "Calgary"],
            "sms_consent_confirmed": "on", "is_active": "on", "notes": "met at a trade show",
        })
        self.assertEqual(response.status_code, 302)
        provider = Provider.objects.get(business_name="New Co")
        self.assertEqual(provider.phone, "+17805550177")
        self.assertEqual(provider.service_areas, ["Edmonton", "Calgary"])
        self.assertTrue(provider.can_text)


@override_settings(**SMS_ON)
class SmsModeTests(AdminFlowBase):
    def test_posting_texts_each_selected_provider_and_marks_them_sent(self):
        self.post_providers(self.a, self.b)
        self.assertEqual(len(self.sent), 2)
        self.assertEqual({m["to"] for m in self.sent}, {"+17805550101", "+17805550102"})
        for message in self.sent:
            self.assertEqual(message["from_"], "+18005550000")
            self.assertIn("Top-Link AI", message["body"])
            self.assertNotIn(CLIENT_PHONE, message["body"])
        offers = LeadOffer.objects.all()
        self.assertEqual({o.status for o in offers}, {LeadOffer.STATUS_SENT})
        self.assertTrue(all(o.sent_at and o.twilio_sid == "SM-fake" for o in offers))

    def test_the_tracker_offers_send_buttons_not_copy_and_paste_marking(self):
        self.post_providers(self.a)
        self.assertNotContains(self.client.get(self.tracker_url), "Mark as sent")

    def test_an_opted_out_provider_is_never_texted(self):
        Provider.objects.filter(pk=self.b.pk).update(sms_opt_out=True)
        self.post_providers(self.a, self.b)
        self.assertEqual(self.sent, [])
        self.assertEqual(LeadOffer.objects.count(), 0)

    def test_a_failed_send_leaves_the_offer_pending_with_the_error(self):
        self.twilio.messages.create.side_effect = TwilioRestException(400, "/x", "Bad number", code=21211)
        response = self.post_providers(self.a, follow=True)
        offer = LeadOffer.objects.get()
        self.assertEqual(offer.status, LeadOffer.STATUS_PENDING)
        self.assertIsNone(offer.sent_at)
        self.assertIn("21211", offer.send_error)
        self.assertContains(response, "Could not text")

    def test_a_stop_block_from_twilio_marks_the_provider_opted_out(self):
        self.twilio.messages.create.side_effect = TwilioRestException(400, "/x", "Blocked", code=21610)
        self.post_providers(self.a)
        self.a.refresh_from_db()
        self.assertTrue(self.a.sms_opt_out)

    def test_one_failure_does_not_stop_the_others(self):
        self.twilio.messages.create.side_effect = [
            TwilioRestException(400, "/x", "Bad number", code=21211), MagicMock(sid="SM-2"),
        ]
        self.post_providers(self.a, self.b)
        statuses = dict(LeadOffer.objects.values_list("provider__business_name", "status"))
        self.assertEqual(statuses, {"Ace Plumbing": "pending", "Best Pipes": "sent"})


# ---------------------------------------------------------------------------
@override_settings(**SMS_ON)
class WebhookTests(TwilioMocked):
    URL = "/api/twilio/sms/"

    def setUp(self):
        super().setUp()
        self.request_obj = make_request()
        self.provider = make_provider()
        self.offer = make_offer(self.request_obj, self.provider, sent_minutes_ago=10)
        self.twilio.messages.create.reset_mock()

    def post(self, body, from_="+17805550101", signed=True, token=TOKEN, url=WEBHOOK_URL, **extra):
        params = {"From": from_, "To": "+18005550000", "Body": body, "MessageSid": "SMin"}
        headers = {}
        if signed:
            headers["HTTP_X_TWILIO_SIGNATURE"] = RequestValidator(token).compute_signature(url, params)
        return self.client.post(self.URL, params, **headers, **extra)

    def test_a_yes_marks_the_offer_accepted_with_a_response_time(self):
        response = self.post(f"YES {self.offer.ref}")
        self.assertEqual(response.status_code, 200)
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.status, LeadOffer.STATUS_ACCEPTED)
        self.assertEqual(self.offer.reply_channel, "sms")
        self.assertAlmostEqual(self.offer.response_time.total_seconds(), 600, delta=30)

    def test_the_clients_phone_is_sent_in_a_second_text_only_after_yes(self):
        self.assertEqual(self.sent, [])
        self.post(f"YES {self.offer.ref}")
        (message,) = self.sent
        self.assertEqual(message["to"], "+17805550101")
        self.assertIn(CLIENT_PHONE, message["body"])
        self.offer.refresh_from_db()
        self.assertIsNotNone(self.offer.client_phone_shared_at)

    def test_a_repeated_yes_does_not_send_the_phone_again(self):
        self.post(f"YES {self.offer.ref}")
        self.post(f"YES {self.offer.ref}")  # Twilio retries / an impatient provider
        self.assertEqual(len(self.sent), 1)

    def test_a_no_declines_and_shares_nothing(self):
        self.post(f"NO {self.offer.ref}")
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.status, LeadOffer.STATUS_DECLINED)
        self.assertIsNotNone(self.offer.response_time)
        self.assertEqual(self.sent, [])

    def test_stop_opts_the_provider_out_and_blocks_further_offers(self):
        response = self.post("STOP")
        self.assertEqual(response.status_code, 200)
        self.provider.refresh_from_db()
        self.assertTrue(self.provider.sms_opt_out)
        with self.assertRaisesMessage(ValueError, "opted out"):
            services.create_offers(make_request(), [self.provider])

    def test_the_other_stop_words_work_too(self):
        for word in ("stop", "STOPALL", "Unsubscribe", "cancel", "END", "quit"):
            Provider.objects.filter(pk=self.provider.pk).update(sms_opt_out=False)
            self.post(word)
            self.provider.refresh_from_db()
            self.assertTrue(self.provider.sms_opt_out, word)

    def test_replies_are_case_and_punctuation_tolerant(self):
        for text in ("yes", "Yes.", "YES!", "y", f"yes #{self.offer.ref}", f"Yes {self.offer.ref}, thanks"):
            LeadOffer.objects.filter(pk=self.offer.pk).update(
                status=LeadOffer.STATUS_SENT, responded_at=None, response_time=None, client_phone_shared_at=None
            )
            self.post(text)
            self.offer.refresh_from_db()
            self.assertEqual(self.offer.status, LeadOffer.STATUS_ACCEPTED, text)

    def test_a_bare_yes_applies_when_the_provider_has_exactly_one_open_offer(self):
        self.post("YES")
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.status, LeadOffer.STATUS_ACCEPTED)

    def test_a_bare_yes_with_several_open_offers_asks_which_one_and_changes_nothing(self):
        second = make_offer(make_request(), self.provider, sent_minutes_ago=5)
        response = self.post("YES")
        body = response.content.decode()
        self.assertIn(str(self.offer.ref), body)
        self.assertIn(str(second.ref), body)
        self.assertIn("<Message>", body)
        self.assertEqual(LeadOffer.objects.filter(status=LeadOffer.STATUS_ACCEPTED).count(), 0)
        self.assertEqual(self.sent, [])

    def test_a_numbered_yes_picks_the_right_offer_among_several(self):
        second = make_offer(make_request(), self.provider, sent_minutes_ago=5)
        self.post(f"YES {second.ref}")
        self.offer.refresh_from_db()
        second.refresh_from_db()
        self.assertEqual((self.offer.status, second.status), (LeadOffer.STATUS_SENT, LeadOffer.STATUS_ACCEPTED))

    def test_another_providers_offer_number_is_not_found(self):
        other = make_provider("Other", "780 555 0188")
        theirs = make_offer(make_request(), other, sent_minutes_ago=5)
        response = self.post(f"YES {theirs.ref}")
        self.assertIn("couldn't find", response.content.decode())
        theirs.refresh_from_db()
        self.assertEqual(theirs.status, LeadOffer.STATUS_SENT)

    def test_a_late_yes_after_the_offer_expired_is_still_honoured(self):
        LeadOffer.objects.filter(pk=self.offer.pk).update(status=LeadOffer.STATUS_EXPIRED)
        self.post(f"YES {self.offer.ref}")
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.status, LeadOffer.STATUS_ACCEPTED)

    def test_an_unknown_sender_is_ignored(self):
        response = self.post(f"YES {self.offer.ref}", from_="+17805559999")
        self.assertEqual(response.status_code, 200)
        self.assertNotIn("<Message>", response.content.decode())
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.status, LeadOffer.STATUS_SENT)

    def test_unrecognised_text_gets_a_hint_only_when_there_is_an_open_offer(self):
        self.assertIn("reply YES", self.post("ok thanks").content.decode())
        self.offer.record_reply(LeadOffer.REPLY_NO, LeadOffer.CHANNEL_SMS)
        self.assertNotIn("<Message>", self.post("ok thanks").content.decode())

    def test_a_yes_still_counts_if_sending_the_clients_phone_fails(self):
        self.twilio.messages.create.side_effect = TwilioRestException(400, "/x", "Down", code=30008)
        response = self.post(f"YES {self.offer.ref}")
        self.assertEqual(response.status_code, 200)
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.status, LeadOffer.STATUS_ACCEPTED)
        self.assertIn("30008", self.offer.send_error)
        self.assertIsNone(self.offer.client_phone_shared_at)

    # ---- the signature is the only gate ----
    def test_a_request_without_a_signature_is_rejected_and_changes_nothing(self):
        self.assertEqual(self.post(f"YES {self.offer.ref}", signed=False).status_code, 403)
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.status, LeadOffer.STATUS_SENT)
        self.assertEqual(self.sent, [])

    def test_a_wrong_signature_is_rejected(self):
        self.assertEqual(self.post(f"YES {self.offer.ref}", token="not-the-token").status_code, 403)
        self.assertEqual(self.post(f"YES {self.offer.ref}", url="http://evil.example/x/").status_code, 403)
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.status, LeadOffer.STATUS_SENT)

    def test_a_tampered_body_is_rejected(self):
        params = {"From": "+17805550101", "To": "+18005550000", "Body": "NO 1", "MessageSid": "SMin"}
        signature = RequestValidator(TOKEN).compute_signature(WEBHOOK_URL, params)
        params["Body"] = f"YES {self.offer.ref}"
        self.assertEqual(self.client.post(self.URL, params, HTTP_X_TWILIO_SIGNATURE=signature).status_code, 403)

    @override_settings(TWILIO_AUTH_TOKEN="")
    def test_without_a_configured_token_nothing_is_accepted(self):
        self.assertEqual(self.post(f"YES {self.offer.ref}", token="").status_code, 403)

    @override_settings(SMS_ENABLED=False)
    def test_with_sms_off_the_webhook_does_nothing(self):
        self.assertEqual(self.post(f"YES {self.offer.ref}").status_code, 403)
        self.offer.refresh_from_db()
        self.assertEqual(self.offer.status, LeadOffer.STATUS_SENT)

    def test_it_does_not_need_the_api_key(self):
        self.assertEqual(self.post(f"NO {self.offer.ref}").status_code, 200)  # no X-API-Key sent

    def test_only_post_is_allowed(self):
        self.assertEqual(self.client.get(self.URL).status_code, 405)

    @override_settings(TWILIO_WEBHOOK_URL="https://public.example.com/api/twilio/sms/")
    def test_the_public_url_can_be_set_explicitly_for_signature_checks(self):
        url = "https://public.example.com/api/twilio/sms/"
        self.assertEqual(self.post(f"NO {self.offer.ref}", url=url).status_code, 200)
        self.assertEqual(self.post(f"NO {self.offer.ref}", url=WEBHOOK_URL).status_code, 403)


# ---------------------------------------------------------------------------
NOW = datetime(2026, 10, 7, 18, 0, tzinfo=dt_timezone.utc)  # 12:00 in Edmonton
NIGHT = datetime(2026, 10, 8, 5, 0, tzinfo=dt_timezone.utc)  # 23:00 in Edmonton


def offer_sent_at(sent_at, **kw):
    request = kw.pop("request", None) or make_request()
    provider = kw.pop("provider", None) or make_provider(f"P{LeadOffer.objects.count()}", f"780 555 01{LeadOffer.objects.count() + 10}")
    offer = LeadOffer.objects.create(service_request=request, provider=provider)
    offer.mark_sent(now=sent_at)
    return offer


@override_settings(**SMS_ON)
class ReminderTests(TwilioMocked):
    def test_a_provider_with_no_reply_gets_one_reminder_after_30_minutes(self):
        offer = offer_sent_at(NOW - timedelta(minutes=31))
        self.assertEqual(jobs.send_reminders(NOW), 1)
        (message,) = self.sent
        self.assertEqual(message["to"], offer.provider.phone)
        self.assertIn(f"YES {offer.ref}", message["body"])
        self.assertNotIn(CLIENT_PHONE, message["body"])
        offer.refresh_from_db()
        self.assertEqual(offer.reminder_sent_at, NOW)
        self.assertEqual(jobs.send_reminders(NOW + timedelta(minutes=15)), 0)  # never twice
        self.assertEqual(len(self.sent), 1)

    def test_nothing_is_sent_before_30_minutes(self):
        offer_sent_at(NOW - timedelta(minutes=29))
        self.assertEqual(jobs.send_reminders(NOW), 0)
        self.assertEqual(self.sent, [])

    def test_providers_who_replied_or_never_got_the_offer_are_not_reminded(self):
        replied = offer_sent_at(NOW - timedelta(hours=1))
        replied.record_reply(LeadOffer.REPLY_NO, LeadOffer.CHANNEL_SMS, now=NOW - timedelta(minutes=50))
        make_offer(make_request(), make_provider("Never", "780 555 0140"))  # still pending
        self.assertEqual(jobs.send_reminders(NOW), 0)

    def test_opted_out_providers_are_skipped(self):
        offer = offer_sent_at(NOW - timedelta(hours=1))
        Provider.objects.filter(pk=offer.provider_id).update(sms_opt_out=True)
        self.assertEqual(jobs.send_reminders(NOW), 0)
        self.assertEqual(self.sent, [])

    def test_no_automatic_texts_in_quiet_hours(self):
        offer_sent_at(NIGHT - timedelta(hours=2))
        self.assertTrue(jobs.in_quiet_hours(NIGHT))
        self.assertFalse(jobs.in_quiet_hours(NOW))
        self.assertEqual(jobs.send_reminders(NIGHT), 0)
        self.assertEqual(self.sent, [])
        self.assertEqual(jobs.send_reminders(NIGHT + timedelta(hours=10)), 1)  # next morning

    @override_settings(SMS_ENABLED=False)
    def test_with_sms_off_no_reminders_are_sent(self):
        offer_sent_at(NOW - timedelta(hours=1))
        self.assertEqual(jobs.send_reminders(NOW), 0)
        self.assertEqual(self.sent, [])

    def test_a_stop_block_marks_the_provider_opted_out_and_is_not_retried(self):
        offer = offer_sent_at(NOW - timedelta(hours=1))
        self.twilio.messages.create.side_effect = TwilioRestException(400, "/x", "Blocked", code=21610)
        self.assertEqual(jobs.send_reminders(NOW), 0)
        offer.provider.refresh_from_db()
        self.assertTrue(offer.provider.sms_opt_out)

    def test_a_failed_reminder_is_retried_on_the_next_run(self):
        offer = offer_sent_at(NOW - timedelta(hours=1))
        self.twilio.messages.create.side_effect = TwilioRestException(500, "/x", "Down", code=30008)
        self.assertEqual(jobs.send_reminders(NOW), 0)
        self.twilio.messages.create.side_effect = None
        self.assertEqual(jobs.send_reminders(NOW + timedelta(minutes=15)), 1)
        offer.refresh_from_db()
        self.assertIsNotNone(offer.reminder_sent_at)


class ExpiryTests(TwilioMocked):
    def test_offers_without_a_reply_after_24_hours_expire(self):
        old = offer_sent_at(NOW - timedelta(hours=25))
        fresh = offer_sent_at(NOW - timedelta(hours=23))
        answered = offer_sent_at(NOW - timedelta(hours=30))
        answered.record_reply(LeadOffer.REPLY_YES, LeadOffer.CHANNEL_SMS, now=NOW - timedelta(hours=29))
        self.assertEqual(jobs.expire_offers(NOW), 1)
        for offer in (old, fresh, answered):
            offer.refresh_from_db()
        self.assertEqual((old.status, fresh.status, answered.status), ("expired", "sent", "accepted"))


class NoYesAlertTests(TwilioMocked):
    def setUp(self):
        super().setUp()
        self.request_obj = make_request()

    @override_settings(ADMIN_ALERT_EMAIL="me@example.com")
    def test_a_request_with_no_yes_two_hours_after_the_first_offer_emails_you_once(self):
        offer_sent_at(NOW - timedelta(hours=3), request=self.request_obj)
        self.assertEqual(jobs.alert_requests_without_yes(NOW), 1)
        (email,) = mail.outbox
        self.assertEqual(email.to, ["me@example.com"])
        self.assertIn(f"request #{self.request_obj.pk}", email.subject)
        self.assertIn("Plumbing", email.body)
        self.assertEqual(jobs.alert_requests_without_yes(NOW + timedelta(minutes=15)), 0)
        self.assertEqual(len(mail.outbox), 1)

    @override_settings(ADMIN_ALERT_EMAIL="me@example.com")
    def test_nothing_before_two_hours(self):
        offer_sent_at(NOW - timedelta(minutes=119), request=self.request_obj)
        self.assertEqual(jobs.alert_requests_without_yes(NOW), 0)
        self.assertEqual(mail.outbox, [])

    @override_settings(ADMIN_ALERT_EMAIL="me@example.com")
    def test_no_alert_once_someone_said_yes(self):
        first = offer_sent_at(NOW - timedelta(hours=3), request=self.request_obj)
        offer_sent_at(NOW - timedelta(hours=3), request=self.request_obj)
        first.record_reply(LeadOffer.REPLY_YES, LeadOffer.CHANNEL_MANUAL, now=NOW - timedelta(hours=2, minutes=30))
        self.assertEqual(jobs.alert_requests_without_yes(NOW), 0)

    @override_settings(ADMIN_ALERT_EMAIL="me@example.com")
    def test_offers_that_were_never_sent_do_not_start_the_clock(self):
        make_offer(self.request_obj, make_provider("Never", "780 555 0140"))
        self.assertEqual(jobs.alert_requests_without_yes(NOW + timedelta(days=2)), 0)

    @override_settings(ADMIN_ALERT_EMAIL="me@example.com", SMS_ENABLED=False)
    def test_it_works_with_sms_off(self):
        offer_sent_at(NOW - timedelta(hours=3), request=self.request_obj)
        self.assertEqual(jobs.alert_requests_without_yes(NOW), 1)

    @override_settings(ADMIN_ALERT_EMAIL="")
    def test_without_an_alert_address_nothing_is_marked_so_it_retries_later(self):
        offer_sent_at(NOW - timedelta(hours=3), request=self.request_obj)
        self.assertEqual(jobs.alert_requests_without_yes(NOW), 0)
        self.request_obj.refresh_from_db()
        self.assertIsNone(self.request_obj.no_yes_alert_sent_at)
        with override_settings(ADMIN_ALERT_EMAIL="me@example.com"):
            self.assertEqual(jobs.alert_requests_without_yes(NOW), 1)


@override_settings(ADMIN_ALERT_EMAIL="me@example.com")
class DailySummaryTests(TwilioMocked):
    def seed(self):
        ServiceRequest.objects.all().delete()
        ServiceRequest.objects.create(
            device_id="d", category="lawn-care", city="Edmonton", phone="1", consent_given=True,
            status=ServiceRequest.STATUS_WAITLISTED,
        )
        made = [make_request() for _ in range(2)]
        for request in made:
            ServiceRequest.objects.filter(pk=request.pk).update(created_at=NOW - timedelta(hours=3))
        ServiceRequest.objects.filter(category="lawn-care").update(created_at=NOW - timedelta(hours=2))
        old = make_request()
        ServiceRequest.objects.filter(pk=old.pk).update(created_at=NOW - timedelta(days=3))

        yes = offer_sent_at(NOW - timedelta(hours=5), request=made[0])
        yes.record_reply(LeadOffer.REPLY_YES, LeadOffer.CHANNEL_SMS, now=NOW - timedelta(hours=5) + timedelta(minutes=10))
        yes.hired = True
        yes.save()
        LeadOffer.objects.filter(pk=yes.pk).update(hired_at=NOW - timedelta(hours=1))
        no = offer_sent_at(NOW - timedelta(hours=4), request=made[0])
        no.record_reply(LeadOffer.REPLY_NO, LeadOffer.CHANNEL_MANUAL, now=NOW - timedelta(hours=4) + timedelta(minutes=30))
        offer_sent_at(NOW - timedelta(hours=2), request=made[1])  # no reply yet
        stale = make_request()
        ServiceRequest.objects.filter(pk=stale.pk).update(created_at=NOW - timedelta(days=3))
        offer_sent_at(NOW - timedelta(days=3), request=stale)  # outside the window

    def test_the_summary_has_every_number_you_asked_for(self):
        self.seed()
        text = jobs.build_daily_summary(NOW)
        self.assertIn("New requests:          3 (1 waitlisted)", text)
        self.assertIn("Offers sent:           3", text)
        self.assertIn("Response rate:         67% (2 of 3)", text)
        self.assertIn("Average response time: 20 min", text)
        self.assertIn("YES replies:           1", text)
        self.assertIn("Hired:                 1", text)
        self.assertIn("Most waitlisted: Lawn Care (1)", text)

    def test_an_empty_day_does_not_divide_by_zero(self):
        text = jobs.build_daily_summary(NOW)
        self.assertIn("New requests:          0", text)
        self.assertIn("n/a (no offers sent)", text)
        self.assertIn("n/a (no replies)", text)

    def test_it_is_sent_once_a_day_after_14_00_utc(self):
        morning = NOW.replace(hour=13, minute=45)
        self.assertFalse(jobs.send_daily_summary_if_due(morning))
        self.assertEqual(mail.outbox, [])
        due = NOW.replace(hour=14, minute=5)
        self.assertTrue(jobs.send_daily_summary_if_due(due))
        self.assertFalse(jobs.send_daily_summary_if_due(due + timedelta(minutes=15)))
        self.assertEqual(len(mail.outbox), 1)
        self.assertEqual(mail.outbox[0].to, ["me@example.com"])
        self.assertTrue(DailySummaryLog.objects.filter(date=due.date()).exists())
        # ...and again the next day
        self.assertTrue(jobs.send_daily_summary_if_due(due + timedelta(days=1)))
        self.assertEqual(len(mail.outbox), 2)

    @override_settings(SMS_ENABLED=False)
    def test_it_works_with_sms_off(self):
        self.assertTrue(jobs.send_daily_summary_if_due(NOW.replace(hour=15)))

    @override_settings(ADMIN_ALERT_EMAIL="")
    def test_without_an_address_it_is_not_logged_as_sent(self):
        self.assertFalse(jobs.send_daily_summary_if_due(NOW.replace(hour=15)))
        self.assertEqual(DailySummaryLog.objects.count(), 0)


class RunLeadJobsCommandTests(TwilioMocked):
    @override_settings(ADMIN_ALERT_EMAIL="me@example.com")
    def test_the_command_runs_every_job_and_with_sms_off_never_touches_twilio(self):
        offer_sent_at(timezone.now() - timedelta(hours=3))
        from io import StringIO

        out = StringIO()
        call_command("run_lead_jobs", stdout=out)
        text = out.getvalue()
        for key in ("reminders_sent: 0", "offers_expired: 0", "no_yes_alerts: 1", "daily_summary_sent"):
            self.assertIn(key, text)
        self.assertEqual(self.sent, [])
