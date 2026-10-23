from datetime import datetime, timedelta
from unittest.mock import patch
from zoneinfo import ZoneInfo

from django.contrib.auth import get_user_model
from django.core import mail
from django.core.cache import cache
from django.test import Client, TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.deletion import delete_account
from accounts.models import UserProfile, UserRole
from catalog.models import Service
from leads import jobs as lead_jobs
from leads.models import LeadOffer
from provider_search.models import ServiceRequest
from providers.models import ProviderProfile

from . import jobs, links
from .campaigns import CAMPAIGNS, active_campaigns
from .dashboard import weekly_report
from .models import InviteCode, InviteSignup, ReminderPreference, ReminderSend

User = get_user_model()
TEST_API_KEY = "test-key"
EDMONTON = ZoneInfo("America/Edmonton")
# 11:00 in Edmonton on a September weekday: inside the send window, furnace-check and window-seals in season.
SEPT_11AM = datetime(2026, 9, 15, 11, 0, tzinfo=EDMONTON)


def signed_in(email="client@example.com", role=UserRole.CUSTOMER, name="Pat Client"):
    user = User.objects.create_user(username=email, email=email)
    UserProfile.objects.create(user=user, role=role, full_name=name)
    token = RefreshToken.for_user(user).access_token
    return user, {"HTTP_X_API_KEY": TEST_API_KEY, "HTTP_AUTHORIZATION": f"Bearer {token}"}


def make_provider(name="Ace Heating", email="ace@example.com", status=ProviderProfile.STATUS_APPROVED):
    user, _ = signed_in(email, UserRole.PROVIDER, f"Owner of {name}")
    return ProviderProfile.objects.create(user=user, business_name=name, phone="+17805550101", email=email, status=status)


def make_request(user, category="hvac", created_at=None, **fields):
    request = ServiceRequest.objects.create(
        user=user, category=category, city="Edmonton", phone="+17805550199", consent_given=True, **fields
    )
    if created_at is not None:
        ServiceRequest.objects.filter(pk=request.pk).update(created_at=created_at)
        request.refresh_from_db()
    return request


def make_offer(request, provider, accepted=True, completed=False, completed_at=None):
    offer = LeadOffer.objects.create(service_request=request, provider=provider)
    if accepted:
        offer.status = LeadOffer.STATUS_ACCEPTED
        offer.sent_at = offer.responded_at = timezone.now()
    if completed:
        offer.hired = offer.job_completed = True
    offer.save()
    if completed_at is not None:
        LeadOffer.objects.filter(pk=offer.pk).update(completed_at=completed_at)
    return offer


@override_settings(API_KEY=TEST_API_KEY)
class AttributionTests(TestCase):
    def setUp(self):
        cache.delete_pattern("rl:*")
        self.user, self.headers = signed_in()

    def _create(self, **extra):
        body = {"category": "plumbing", "phone": "780 555 0199", "consent": True, **extra}
        response = self.client.post("/api/requests/", body, content_type="application/json", **self.headers)
        self.assertEqual(response.status_code, 201, response.content)
        return ServiceRequest.objects.get(pk=response.json()["request_id"])

    def test_no_source_is_direct(self):
        request = self._create()
        self.assertEqual((request.source, request.source_ref), ("direct", ""))

    def test_seo_page_and_neighbourhood_refs_are_kept(self):
        self.assertEqual(self._create(source="seo", source_ref="windermere").source_ref, "windermere")
        self.assertEqual(self._create(source="seo", source_ref="plumber-edmonton").source_ref, "plumber-edmonton")

    def test_unknown_refs_are_dropped_but_the_channel_is_kept(self):
        request = self._create(source="seo", source_ref="not-a-place")
        self.assertEqual((request.source, request.source_ref), ("seo", ""))
        request = self._create(source="seasonal", source_ref="<script>")
        self.assertEqual((request.source, request.source_ref), ("seasonal", ""))

    def test_seasonal_campaign_ref(self):
        request = self._create(source="seasonal", source_ref="furnace-check")
        self.assertEqual((request.source, request.source_ref), ("seasonal", "furnace-check"))

    def test_unknown_source_is_direct(self):
        self.assertEqual(self._create(source="billboard", source_ref="x").source, "direct")
        self.assertEqual(self._create(source=["seo"]).source, "direct")

    def test_an_invited_clients_first_request_counts_for_the_invite_and_later_ones_dont(self):
        inviter, _ = signed_in("friend@example.com")
        code = InviteCode.for_user(inviter)
        InviteSignup.objects.create(invitee=self.user, invite=code, code=code.code)
        first = self._create()
        second = self._create()
        self.assertEqual((first.source, first.source_ref), ("invite", code.code))
        self.assertEqual(second.source, "direct")

    def test_explicit_invite_source_needs_a_real_code_that_isnt_their_own(self):
        inviter, _ = signed_in("friend@example.com")
        code = InviteCode.for_user(inviter)
        own = InviteCode.for_user(self.user)
        self.assertEqual(self._create(source="invite", source_ref=code.code.lower()).source_ref, code.code)
        self.assertEqual(self._create(source="invite", source_ref=own.code).source_ref, "")


@override_settings(API_KEY=TEST_API_KEY)
class InviteApiTests(TestCase):
    def setUp(self):
        cache.delete_pattern("rl:*")
        self.inviter, self.inviter_h = signed_in("friend@example.com", name="Sam Friend")
        self.new_user, self.new_h = signed_in("new@example.com")

    def _claim(self, code, headers=None, **extra):
        return self.client.post(
            "/api/growth/invite/claim/", {"code": code, **extra}, content_type="application/json", **(headers or self.new_h)
        )

    def test_invite_link_is_made_once_and_stays_the_same(self):
        first = self.client.get("/api/growth/invite/", **self.inviter_h).json()
        second = self.client.get("/api/growth/invite/", **self.inviter_h).json()
        self.assertEqual(first["code"], second["code"])
        self.assertEqual(len(first["code"]), 8)
        self.assertTrue(first["url"].endswith(f"/invite/{first['code']}/"))
        self.assertIn(first["url"], first["share_text"])
        self.assertEqual(InviteCode.objects.count(), 1)

    def test_providers_and_signed_out_people_get_no_invite(self):
        provider = make_provider()
        token = RefreshToken.for_user(provider.user).access_token
        provider_h = {"HTTP_X_API_KEY": TEST_API_KEY, "HTTP_AUTHORIZATION": f"Bearer {token}"}
        self.assertEqual(self.client.get("/api/growth/invite/", **provider_h).status_code, 403)
        self.assertEqual(self.client.get("/api/growth/invite/", HTTP_X_API_KEY=TEST_API_KEY).status_code, 401)

    def test_claim_records_the_signup_and_the_shared_provider(self):
        code = InviteCode.for_user(self.inviter)
        provider = make_provider()
        response = self._claim(code.code.lower(), provider_id=provider.pk)
        self.assertEqual(response.status_code, 201)
        signup = InviteSignup.objects.get(invitee=self.new_user)
        self.assertEqual((signup.invite, signup.code, signup.shared_provider), (code, code.code, provider))
        self.assertEqual(self.client.get("/api/growth/invite/", **self.inviter_h).json()["signups"], 1)

    def test_an_unapproved_provider_is_not_recorded(self):
        code = InviteCode.for_user(self.inviter)
        pending = make_provider(status=ProviderProfile.STATUS_PENDING)
        self.assertEqual(self._claim(code.code, provider_id=pending.pk).status_code, 201)
        self.assertIsNone(InviteSignup.objects.get().shared_provider)

    def test_claim_rules(self):
        code = InviteCode.for_user(self.inviter)
        own = InviteCode.for_user(self.new_user)
        self.assertEqual(self._claim("NOPE1234").status_code, 400)
        self.assertEqual(self._claim("").status_code, 400)
        self.assertEqual(self._claim(own.code).status_code, 400)
        self.assertEqual(self._claim(code.code).status_code, 201)
        self.assertEqual(self._claim(code.code).status_code, 409)  # only once
        old, old_h = signed_in("old@example.com")
        User.objects.filter(pk=old.pk).update(date_joined=timezone.now() - timedelta(days=31))
        self.assertEqual(self._claim(code.code, headers=old_h).status_code, 409)
        self.assertEqual(InviteSignup.objects.count(), 1)

    def test_a_deleted_inviters_code_no_longer_works(self):
        code = InviteCode.for_user(self.inviter).code
        delete_account(self.inviter)
        self.assertFalse(InviteCode.objects.filter(code=code).exists())
        self.assertEqual(self._claim(code).status_code, 400)

    def test_claims_are_rate_limited(self):
        for _ in range(10):
            self._claim("NOPE1234")
        self.assertEqual(self._claim("NOPE1234").status_code, 429)


@override_settings(API_KEY=TEST_API_KEY)
class ReminderPreferenceApiTests(TestCase):
    def setUp(self):
        self.user, self.headers = signed_in()

    def test_on_by_default_and_can_be_switched_off_and_on(self):
        url = "/api/growth/reminders/"
        self.assertTrue(self.client.get(url, **self.headers).json()["seasonal_reminders"])
        response = self.client.patch(url, {"seasonal_reminders": False}, content_type="application/json", **self.headers)
        self.assertFalse(response.json()["seasonal_reminders"])
        self.assertEqual(ReminderPreference.objects.get(user=self.user).changed_via, "app")
        self.assertFalse(self.client.get(url, **self.headers).json()["seasonal_reminders"])
        self.client.patch(url, {"seasonal_reminders": True}, content_type="application/json", **self.headers)
        self.assertTrue(ReminderPreference.enabled_for(self.user))

    def test_rejects_anything_but_a_boolean(self):
        response = self.client.patch(
            "/api/growth/reminders/", {"seasonal_reminders": "no"}, content_type="application/json", **self.headers
        )
        self.assertEqual(response.status_code, 400)
        self.assertTrue(ReminderPreference.enabled_for(self.user))


class GrowthWebPageTests(TestCase):
    def setUp(self):
        self.user, _ = signed_in()

    def test_open_request_page_links_into_the_app_with_the_source(self):
        response = self.client.get("/open/request/?service=hvac&src=seasonal&ref=furnace-check")
        self.assertEqual(response.status_code, 200)
        html = response.content.decode()
        self.assertIn("tabmatch://open/request?service=hvac&amp;src=seasonal&amp;ref=furnace-check", html)
        self.assertIn('content="noindex,nofollow"', html)
        self.assertIn("Get the Tabmatch app", html)

    def test_open_request_drops_unknown_sources(self):
        html = self.client.get("/open/request/?service=hvac&src=evil&ref=x").content.decode()
        self.assertIn('href="tabmatch://open/request?service=hvac"', html)

    def test_open_request_needs_a_launched_service(self):
        Service.objects.filter(slug="hvac").update(is_launched=False)
        self.assertEqual(self.client.get("/open/request/?service=hvac").status_code, 404)
        self.assertEqual(self.client.get("/open/request/?service=nope").status_code, 404)

    def test_invite_page(self):
        code = InviteCode.for_user(self.user).code
        provider = make_provider("Ace Heating")
        html = self.client.get(f"/invite/{code}/?provider={provider.pk}").content.decode()
        self.assertIn("Ace Heating", html)
        self.assertIn(f"tabmatch://open/invite?code={code}&amp;provider={provider.pk}", html)
        self.assertIn(code, html)
        self.assertEqual(self.client.get("/invite/NOPE1234/").status_code, 404)
        pending = make_provider("Hidden Co", "hidden@example.com", ProviderProfile.STATUS_PENDING)
        self.assertNotIn("Hidden Co", self.client.get(f"/invite/{code}/?provider={pending.pk}").content.decode())

    def test_unsubscribe_needs_a_post_and_a_valid_token(self):
        path = links.unsubscribe_path(self.user)
        response = self.client.get(path)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(ReminderPreference.enabled_for(self.user))  # a link scanner opening it changes nothing
        self.assertEqual(self.client.get("/reminders/unsubscribe/forged-token/").status_code, 404)
        # Mail apps' one-click unsubscribe POSTs without a CSRF token.
        response = Client(enforce_csrf_checks=True).post(path, {"List-Unsubscribe": "One-Click"})
        self.assertEqual(response.status_code, 200)
        self.assertIn("unsubscribed", response.content.decode())
        pref = ReminderPreference.objects.get(user=self.user)
        self.assertEqual((pref.seasonal_reminders, pref.changed_via), (False, "email"))

    def test_robots_keeps_these_pages_out_of_search(self):
        robots = self.client.get("/robots.txt").content.decode()
        for path in ("/open/", "/invite/", "/reminders/"):
            self.assertIn(f"Disallow: {path}", robots)


@override_settings(
    SEASONAL_REMINDERS_ENABLED=True,
    SITE_URL="https://tabmatch.example",
    BUSINESS_MAILING_ADDRESS="Tabmatch, 10000 Jasper Ave, Edmonton AB",
    SEASONAL_REMINDERS_DAILY_CAP=150,
)
class SeasonalReminderJobTests(TestCase):
    def setUp(self):
        self.provider = make_provider()
        self.user, _ = signed_in("pat@example.com", name="Pat Client")
        request = make_request(self.user, "hvac", created_at=SEPT_11AM - timedelta(days=300))
        make_offer(request, self.provider, completed=True, completed_at=SEPT_11AM - timedelta(days=290))
        patcher = patch("growth.jobs.push.send_to_user", return_value=1)
        self.push = patcher.start()
        self.addCleanup(patcher.stop)

    def run_job(self, when=SEPT_11AM):
        return jobs.send_seasonal_reminders(when)

    def test_a_past_client_gets_one_push_and_one_email(self):
        self.assertEqual(self.run_job(), 1)
        log = ReminderSend.objects.get()
        self.assertEqual((log.user, log.campaign, log.service, log.season_year), (self.user, "furnace-check", "hvac", 2026))
        self.assertEqual((log.push_count, log.email_sent), (1, True))

        _, kwargs = self.push.call_args
        self.assertEqual(kwargs["data"], {"type": "request_prefill", "service": "hvac", "source": "seasonal", "ref": "furnace-check"})

        self.assertEqual(len(mail.outbox), 1)
        email = mail.outbox[0]
        self.assertEqual(email.to, ["pat@example.com"])
        self.assertIn("Hi Pat,", email.body)
        self.assertIn("https://tabmatch.example/open/request/?service=hvac&src=seasonal&ref=furnace-check", email.body)
        unsubscribe = "https://tabmatch.example" + links.unsubscribe_path(self.user)
        self.assertIn(unsubscribe, email.body)
        self.assertIn("10000 Jasper Ave", email.body)
        self.assertEqual(email.extra_headers["List-Unsubscribe"], f"<{unsubscribe}>")
        self.assertEqual(email.extra_headers["List-Unsubscribe-Post"], "List-Unsubscribe=One-Click")

    def test_at_most_one_reminder_a_month(self):
        self.assertEqual(self.run_job(), 1)
        self.assertEqual(self.run_job(SEPT_11AM + timedelta(hours=2)), 0)
        self.assertEqual(self.run_job(SEPT_11AM + timedelta(days=10)), 0)
        self.assertEqual(ReminderSend.objects.count(), 1)

    def test_the_same_campaign_isnt_sent_twice_in_a_season(self):
        self.run_job()
        self.assertEqual(self.run_job(datetime(2026, 10, 20, 11, 0, tzinfo=EDMONTON)), 0)

    def test_a_used_service_comes_before_one_they_may_need(self):
        plumbing = make_request(self.user, "plumbing", created_at=SEPT_11AM - timedelta(days=100))
        make_offer(plumbing, self.provider, completed=True, completed_at=SEPT_11AM - timedelta(days=90))
        # October: furnace-check (hvac: used), window-seals (not their audience), winterize taps (plumbing: used).
        self.assertEqual(self.run_job(datetime(2026, 10, 1, 11, 0, tzinfo=EDMONTON)), 1)
        self.assertEqual(ReminderSend.objects.get().campaign, "furnace-check")
        # November: the other October campaign is out of season, and furnace-check is done for the year.
        self.assertEqual(self.run_job(datetime(2026, 11, 5, 11, 0, tzinfo=EDMONTON)), 0)

    def test_opted_out_clients_get_nothing(self):
        ReminderPreference.set_for(self.user, False, ReminderPreference.VIA_EMAIL)
        self.assertEqual(self.run_job(), 0)
        self.push.assert_not_called()
        self.assertEqual(mail.outbox, [])

    def test_only_inside_the_send_window_and_only_when_enabled(self):
        self.assertEqual(self.run_job(SEPT_11AM.replace(hour=8)), 0)
        self.assertEqual(self.run_job(SEPT_11AM.replace(hour=19)), 0)
        with override_settings(SEASONAL_REMINDERS_ENABLED=False):
            self.assertEqual(self.run_job(), 0)
        self.assertEqual(self.run_job(SEPT_11AM.replace(month=8)), 0)  # no campaign in August

    def test_old_inquiries_without_a_completed_job_are_not_contacted(self):
        other, _ = signed_in("old@example.com")
        make_request(other, "hvac", created_at=SEPT_11AM - timedelta(days=200))
        recent, _ = signed_in("recent@example.com")
        make_request(recent, "hvac", created_at=SEPT_11AM - timedelta(days=120))
        self.run_job()
        self.assertEqual(set(ReminderSend.objects.values_list("user__email", flat=True)), {"pat@example.com", "recent@example.com"})

    def test_a_client_who_just_asked_for_the_service_is_skipped(self):
        make_request(self.user, "hvac", created_at=SEPT_11AM - timedelta(days=20))
        self.assertEqual(self.run_job(), 0)

    def test_providers_inactive_accounts_and_other_cities_are_never_reminded(self):
        provider_request = make_request(self.provider.user, "hvac", created_at=SEPT_11AM - timedelta(days=90))
        self.assertIsNotNone(provider_request)
        gone, _ = signed_in("gone@example.com")
        make_request(gone, "hvac", created_at=SEPT_11AM - timedelta(days=90))
        User.objects.filter(pk=gone.pk).update(is_active=False)
        calgary, _ = signed_in("calgary@example.com")
        ServiceRequest.objects.filter(pk=make_request(calgary, "hvac").pk).update(
            city="Calgary", created_at=SEPT_11AM - timedelta(days=90)
        )
        self.run_job()
        self.assertEqual(list(ReminderSend.objects.values_list("user__email", flat=True)), ["pat@example.com"])

    def test_campaigns_for_services_that_arent_launched_are_skipped(self):
        Service.objects.filter(slug="hvac").update(is_launched=False)
        self.assertEqual(self.run_job(), 0)

    def test_daily_cap(self):
        for i in range(3):
            user, _ = signed_in(f"c{i}@example.com")
            make_request(user, "hvac", created_at=SEPT_11AM - timedelta(days=90))
        with override_settings(SEASONAL_REMINDERS_DAILY_CAP=2):
            self.assertEqual(self.run_job(), 2)
            self.assertEqual(self.run_job(SEPT_11AM + timedelta(minutes=15)), 0)
        self.assertEqual(ReminderSend.objects.count(), 2)

    def test_without_a_mailing_address_it_is_push_only(self):
        with override_settings(BUSINESS_MAILING_ADDRESS=""):
            self.assertEqual(self.run_job(), 1)
        self.assertEqual(mail.outbox, [])
        self.assertFalse(ReminderSend.objects.get().email_sent)

    def test_nothing_reached_them_means_no_log_so_they_can_be_reminded_later(self):
        self.push.return_value = 0
        with override_settings(BUSINESS_MAILING_ADDRESS=""):
            self.assertEqual(self.run_job(), 0)
        self.assertFalse(ReminderSend.objects.exists())

    def test_an_email_failure_stops_the_run(self):
        self.push.return_value = 0
        second, _ = signed_in("second@example.com")
        make_request(second, "hvac", created_at=SEPT_11AM - timedelta(days=90))
        with patch("growth.jobs.EmailMessage.send", side_effect=OSError("smtp down")) as send:
            self.assertEqual(self.run_job(), 0)
        self.assertEqual(send.call_count, 1)
        self.assertFalse(ReminderSend.objects.exists())

    def test_the_cron_job_runs_it(self):
        with patch("growth.jobs.send_seasonal_reminders", return_value=3):
            self.assertEqual(lead_jobs.run_all(SEPT_11AM)["seasonal_reminders"], 3)
        with patch("growth.jobs.send_seasonal_reminders", side_effect=RuntimeError("boom")):
            self.assertEqual(lead_jobs.run_all(SEPT_11AM)["seasonal_reminders"], 0)


class CampaignConfigTests(TestCase):
    def test_every_campaign_is_well_formed(self):
        slugs = [c.slug for c in CAMPAIGNS]
        self.assertEqual(len(slugs), len(set(slugs)))
        services = set(Service.objects.values_list("slug", flat=True))
        for c in CAMPAIGNS:
            with self.subTest(c.slug):
                self.assertIn(c.service, services)
                self.assertIn(c.service, c.audience)
                self.assertTrue(set(c.audience) <= services)
                self.assertTrue(all(1 <= m <= 12 for m in c.months))
                self.assertLessEqual(len(c.push_body), 110)

    def test_the_seasons_asked_for(self):
        launched = set(Service.objects.filter(is_launched=True).values_list("slug", flat=True))
        self.assertIn("furnace-check", [c.slug for c in active_campaigns(9, launched)])
        self.assertIn("furnace-check", [c.slug for c in active_campaigns(10, launched)])
        self.assertIn("ac-check", [c.slug for c in active_campaigns(4, launched)])
        self.assertIn("ac-check", [c.slug for c in active_campaigns(5, launched)])
        self.assertIn("exterior-painting", [c.slug for c in active_campaigns(5, launched)])
        self.assertIn("exterior-painting", [c.slug for c in active_campaigns(6, launched)])


class DashboardTests(TestCase):
    def setUp(self):
        self.provider = make_provider()
        self.user, _ = signed_in()
        now = timezone.now()
        make_offer(make_request(self.user, source="seo", source_ref="windermere"), self.provider, completed=True)
        make_offer(make_request(self.user, source="seo", source_ref="windermere"), self.provider)
        make_request(self.user, source="seo", source_ref="glenora")
        make_offer(make_request(self.user, source="seasonal", source_ref="furnace-check"), self.provider, accepted=False)
        make_request(self.user, source="invite", source_ref="ABCDEFGH")
        make_request(self.user)
        make_request(self.user, created_at=now - timedelta(days=200))  # outside the 12 weeks
        ReminderSend.objects.create(user=self.user, campaign="furnace-check", service="hvac", season_year=2026)

    def test_weekly_counts_by_source_with_conversion(self):
        report = weekly_report(12)
        self.assertEqual(report["columns"], ["Direct", "SEO page", "Seasonal reminder", "Invite", "All"])
        self.assertEqual(len(report["rows"]), 12)
        this_week = report["rows"][0]
        direct, seo, seasonal, invite, everything = this_week["cells"]
        self.assertEqual((seo["requests"], seo["accepted"], seo["completed"]), (3, 2, 1))
        self.assertEqual((seo["accepted_rate"], seo["completed_rate"]), (67, 33))
        self.assertEqual((seasonal["requests"], seasonal["accepted"]), (1, 0))
        self.assertEqual((invite["requests"], direct["requests"], everything["requests"]), (1, 1, 6))
        self.assertIsNone(report["rows"][1]["cells"][0]["accepted_rate"])
        self.assertEqual(this_week["reminders_sent"], 1)
        self.assertEqual(report["totals"][4]["requests"], 6)
        seo_refs = next(g for g in report["top_refs"] if g["label"] == "SEO page")["refs"]
        self.assertEqual(seo_refs[0], ("windermere", 2))

    def test_admin_page(self):
        admin_user = User.objects.create_superuser(username="boss", email="boss@example.com", password="x")
        self.client.force_login(admin_user)
        response = self.client.get(reverse("admin:growth_growthreport_changelist") + "?weeks=4")
        self.assertEqual(response.status_code, 200)
        html = response.content.decode()
        self.assertIn("Growth dashboard", html)
        self.assertIn("SEO page", html)
        self.assertIn("windermere", html)
        self.assertEqual(self.client.get(reverse("admin:growth_growthreport_changelist") + "?weeks=x").status_code, 200)

    def test_admin_page_is_staff_only(self):
        self.client.force_login(self.user)
        response = self.client.get(reverse("admin:growth_growthreport_changelist"))
        self.assertNotEqual(response.status_code, 200)
