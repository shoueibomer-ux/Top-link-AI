import json
from io import StringIO

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.db import connection, transaction
from django.test import TestCase
from django.utils import timezone

from accounts.models import ProviderBusinessProfile, UserProfile, UserRole
from catalog.models import Service
from leads.models import LeadOffer, Provider as ManualProvider
from matching.models import Profile as MatchingProfile
from provider_search.models import ProviderOnboarding, ServiceRequest

from .audit import WriteAttempted, build_report, read_only_guard
from .models import GoogleIdentity, ProviderProfile

User = get_user_model()


def make_user(email, role):
    user = User.objects.create_user(username=email, email=email)
    UserProfile.objects.create(user=user, role=role)
    return user


def make_request(category="plumbing"):
    return ServiceRequest.objects.create(
        device_id="d", category=category, city="Edmonton", phone="+17805550199", consent_given=True
    )


class AuditCase(TestCase):
    def seed(self):
        plumbing = Service.objects.get(slug="plumbing")

        # Hand-added providers.
        self.m1 = ManualProvider.objects.create(
            business_name="Ace", phone="780 555 0101", service_areas=["Edmonton"], sms_consent_confirmed=True
        )
        self.m1.services.set([plumbing])
        self.m2 = ManualProvider.objects.create(business_name="Broken", phone="123", sms_opt_out=True)
        self.m3 = ManualProvider.objects.create(
            business_name="Abroad", phone="+44 20 7946 0958", service_areas=["Calgary"], is_active=False
        )
        self.m3.services.set([plumbing])

        # Lead offers: one waiting for a reply, one never sent, one hired.
        waiting = LeadOffer.objects.create(service_request=make_request(), provider=self.m1)
        waiting.mark_sent()
        LeadOffer.objects.create(service_request=make_request(), provider=self.m3)
        done = LeadOffer.objects.create(service_request=make_request(), provider=self.m2, hired=True)
        done.mark_sent()
        done.record_reply(LeadOffer.REPLY_YES, LeadOffer.CHANNEL_MANUAL)

        # Email/password providers.
        self.user_a = make_user("anna@example.com", UserRole.PROVIDER)
        self.business_a = ProviderBusinessProfile.objects.create(
            user=self.user_a, business_name="Anna Co", phone="(780) 555-0101",  # same number as Ace
            categories=["plumbing", "not-a-slug"], city="Atlantis",
        )
        # One account with both an email/password and a Google profile.
        self.user_b = make_user("bob@example.com", UserRole.PROVIDER)
        ProviderBusinessProfile.objects.create(user=self.user_b, business_name="Bob Co", phone="587 555 0102", city="Calgary")
        self.google_b = ProviderProfile.objects.create(
            user=self.user_b, business_name="Bob Co", phone="+15875550102", email="bob@example.com",
            cities=["Calgary"], status=ProviderProfile.STATUS_APPROVED,
        )
        GoogleIdentity.objects.create(user=self.user_b, sub="sub-bob")
        # A provider account with no profile, a customer and an admin.
        make_user("eve@example.com", UserRole.PROVIDER)
        make_user("carl@example.com", UserRole.CUSTOMER)
        make_user("root@example.com", UserRole.ADMIN)

        ProviderOnboarding.objects.create(provider_id="demo-1")
        MatchingProfile.objects.create(name="Proto", role="business", lat=53.5, lng=-113.5)


class ReportTests(AuditCase):
    def test_an_empty_database_gives_zeros_and_no_notes(self):
        report = build_report()
        self.assertEqual(report["leads_provider"]["total"], 0)
        self.assertEqual(report["lead_offers"]["total"], 0)
        self.assertEqual(report["business_profiles"]["total"], 0)
        self.assertEqual(report["provider_profiles"]["by_status"], {"pending": 0, "approved": 0, "rejected": 0})
        self.assertEqual((report["duplicates"], report["notes"]), ([], []))

    def test_it_counts_hand_added_providers(self):
        self.seed()
        manual = build_report()["leads_provider"]
        self.assertEqual(manual["total"], 3)
        self.assertEqual(manual["active"], 2)
        self.assertEqual(manual["sms_opt_out"], 1)
        self.assertEqual(manual["sms_consent_confirmed"], 1)
        self.assertEqual(manual["no_services"], 1)
        self.assertEqual(manual["no_service_areas"], 1)
        self.assertEqual(manual["unreadable_phone_ids"], [self.m2.pk])
        self.assertEqual(manual["non_north_american_phone_ids"], [self.m3.pk])

    def test_it_counts_lead_offers_and_the_ones_still_in_flight(self):
        self.seed()
        offers = build_report()["lead_offers"]
        self.assertEqual(offers["total"], 3)
        self.assertEqual(offers["by_status"]["sent"], 1)
        self.assertEqual(offers["by_status"]["pending"], 1)
        self.assertEqual(offers["by_status"]["accepted"], 1)
        self.assertEqual((offers["awaiting_reply"], offers["created_but_never_sent"], offers["hired"]), (1, 1, 1))
        self.assertEqual(offers["providers_with_offers"], 3)

    def test_it_counts_accounts_and_provider_profiles(self):
        self.seed()
        report = build_report()
        self.assertEqual(report["accounts"], {
            "provider_accounts": 3, "customer_accounts": 1, "admin_accounts": 1,
            "provider_accounts_without_any_profile": 1,
        })
        business = report["business_profiles"]
        self.assertEqual(business["total"], 2)
        self.assertEqual(business["categories_not_in_catalog"], {"not-a-slug": 1})
        self.assertEqual(business["cities_not_in_the_four"], {"Atlantis": 1})
        self.assertEqual(business["with_categories"], 1)
        self.assertEqual(report["provider_profiles"]["by_status"]["approved"], 1)
        self.assertEqual(report["provider_profiles"]["with_google_identity"], 1)
        self.assertEqual(report["users_with_both_a_business_profile_and_a_provider_profile"], [self.user_b.pk])

    def test_it_reports_the_other_provider_like_tables_that_are_not_merged(self):
        self.seed()
        other = build_report()["not_part_of_the_merge"]
        # The database already holds demo onboarding rows from an earlier migration, so compare with what is there.
        rows = list(ProviderOnboarding.objects.all())
        self.assertGreaterEqual(len(rows), 1)
        self.assertEqual(other["provider_onboarding_demo_total"], len(rows))
        self.assertEqual(other["provider_onboarding_demo_complete"], sum(1 for r in rows if r.is_complete))
        self.assertEqual(other["matching_profile_prototype_total"], MatchingProfile.objects.count())
        self.assertGreaterEqual(other["matching_profile_prototype_total"], 1)


class DuplicateTests(AuditCase):
    def test_the_same_number_on_different_people_is_flagged_whatever_its_formatting(self):
        self.seed()
        duplicates = build_report(show_details=True)["duplicates"]
        phone = next(d for d in duplicates if d["matched_on"] == "phone: +17805550101")
        self.assertEqual(
            phone["records"],
            [f"accounts.ProviderBusinessProfile#{self.business_a.pk}", f"leads.Provider#{self.m1.pk}"],
        )
        self.assertFalse(phone["same_account"])

    def test_one_account_with_two_profiles_is_marked_as_the_same_account(self):
        self.seed()
        same = [d for d in build_report(show_details=True)["duplicates"] if d["same_account"]]
        self.assertTrue(same)
        for dup in same:
            self.assertTrue(any("ProviderProfile" in r for r in dup["records"]))
            self.assertTrue(any("ProviderBusinessProfile" in r for r in dup["records"]))

    def test_contact_details_are_masked_unless_asked_for(self):
        self.seed()
        masked = json.dumps(build_report())
        for secret in ("7805550101", "bob@example.com", "5875550102"):
            self.assertNotIn(secret, masked)
        self.assertIn("+1780***0101", masked)
        self.assertIn("b***@example.com", masked)
        self.assertIn("7805550101", json.dumps(build_report(show_details=True)))

    def test_a_unique_number_is_not_a_duplicate(self):
        ManualProvider.objects.create(business_name="A", phone="780 555 0111")
        ManualProvider.objects.create(business_name="B", phone="780 555 0112")
        self.assertEqual(build_report()["duplicates"], [])


class NotesTests(AuditCase):
    def test_in_flight_offers_are_a_blocker_and_listed_first(self):
        self.seed()
        notes = build_report()["notes"]
        self.assertEqual(notes[0]["level"], "blocker")
        self.assertIn("awaiting a provider's reply", notes[0]["text"])
        levels = [n["level"] for n in notes]
        self.assertEqual(levels, sorted(levels, key=["blocker", "warning", "note"].index))

    def test_data_problems_are_called_out(self):
        self.seed()
        text = " ".join(n["text"] for n in build_report()["notes"])
        self.assertIn("can't be read", text)  # the unreadable hand-added phone
        self.assertIn("not-a-slug", text)
        self.assertIn("Atlantis", text)
        self.assertIn("opted out", text)
        self.assertIn("different people/accounts", text)

    def test_a_clean_database_has_no_blockers(self):
        ManualProvider.objects.create(business_name="A", phone="780 555 0111", sms_consent_confirmed=True)
        self.assertEqual([n for n in build_report()["notes"] if n["level"] == "blocker"], [])


class ReadOnlyTests(AuditCase):
    def snapshot(self):
        return (
            ManualProvider.objects.count(), LeadOffer.objects.count(), ProviderBusinessProfile.objects.count(),
            ProviderProfile.objects.count(), User.objects.count(), UserProfile.objects.count(),
        )

    def test_the_guard_refuses_writes(self):
        existing = ManualProvider.objects.create(business_name="keep me", phone="780 555 0100")
        with read_only_guard():
            # Each refused write gets its own savepoint so it can't poison the test's transaction.
            with self.assertRaises(WriteAttempted), transaction.atomic():
                ManualProvider.objects.create(business_name="x", phone="780 555 0101")
            with self.assertRaises(WriteAttempted), transaction.atomic():
                existing.delete()
            with self.assertRaises(WriteAttempted), transaction.atomic():
                ManualProvider.objects.filter(pk=existing.pk).update(business_name="changed")
            # Reading is still fine inside the guard.
            self.assertEqual(ManualProvider.objects.count(), 1)
        existing.refresh_from_db()
        self.assertEqual(existing.business_name, "keep me")

    def test_running_the_audit_writes_nothing(self):
        self.seed()
        before = self.snapshot()
        statements = []

        def record(execute, sql, params, many, context):
            statements.append(sql)
            return execute(sql, params, many, context)

        with connection.execute_wrapper(record):
            call_command("audit_providers", stdout=StringIO())
        self.assertEqual(self.snapshot(), before)
        self.assertFalse([s for s in statements if s.lstrip().upper().startswith(("INSERT", "UPDATE", "DELETE"))])
        self.assertTrue(statements)  # it did read

    def test_it_does_not_touch_timestamps_or_status(self):
        self.seed()
        stamp = (
            ProviderProfile.objects.get().updated_at,
            list(LeadOffer.objects.order_by("pk").values_list("status", "sent_at")),
        )
        call_command("audit_providers", stdout=StringIO())
        again = (
            ProviderProfile.objects.get().updated_at,
            list(LeadOffer.objects.order_by("pk").values_list("status", "sent_at")),
        )
        self.assertEqual(stamp, again)
        self.assertLess(ProviderProfile.objects.get().updated_at, timezone.now())


class CommandTests(AuditCase):
    def run_command(self, *args):
        out = StringIO()
        call_command("audit_providers", *args, stdout=out)
        return out.getvalue()

    def test_the_text_report_says_it_is_read_only_and_lists_each_kind(self):
        self.seed()
        text = self.run_command()
        self.assertIn("read-only: nothing was changed", text)
        for heading in (
            "Hand-added providers (leads.Provider)", "Lead offers", "Accounts",
            "Email/password provider profiles", "Google sign-in provider profiles", "Not part of the merge",
            "Possible duplicates", "What to deal with", "[BLOCKER]",
        ):
            self.assertIn(heading, text)
        self.assertNotIn("7805550101", text)

    def test_details_shows_full_contact_details(self):
        self.seed()
        self.assertIn("+17805550101", self.run_command("--details"))

    def test_json_output_is_valid_and_complete(self):
        self.seed()
        report = json.loads(self.run_command("--json"))
        self.assertTrue(report["read_only"])
        self.assertEqual(report["leads_provider"]["total"], 3)
        self.assertIn("notes", report)

    def test_it_runs_on_an_empty_database(self):
        self.assertIn("Nothing flagged.", self.run_command())
        self.assertEqual(json.loads(self.run_command("--json"))["lead_offers"]["total"], 0)
