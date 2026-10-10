from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase, override_settings

from accounts.models import UserProfile, UserRole
from catalog.models import Service

from .apps import check_dev_fake_auth
from .models import GoogleIdentity, ProviderProfile

User = get_user_model()
API_KEY = "test-key"
CLIENT_ID = "web-client-id.apps.googleusercontent.com"
SIGN_IN = "/api/provider/auth/google/"
PROFILE = "/api/provider/profile/"
MATCHES = "/api/provider/matches/"
KEY = {"HTTP_X_API_KEY": API_KEY}


def google_info(email="pro@example.com", sub="sub-1", name="Pat Provider", **overrides):
    return {"aud": CLIENT_ID, "email": email, "email_verified": True, "sub": sub, "name": name, **overrides}


GOOD_PROFILE = {
    "business_name": "Ace Plumbing",
    "phone": "(780) 555-0100",
    "email": "office@ace.example",
    "categories": ["plumbing", "hvac"],
    "cities": ["Edmonton", "Calgary"],
    "bio": "Family-run since 2005.",
}


@override_settings(API_KEY=API_KEY, GOOGLE_OAUTH_CLIENT_IDS=[CLIENT_ID], GOOGLE_DEV_FAKE_AUTH=False)
class ProviderApiCase(TestCase):
    """Google's verification is mocked: no test here reaches the network."""

    def setUp(self):
        cache.clear()  # the sign-in rate limit lives in the shared cache

    def sign_in(self, token="good-token", **info):
        with patch("providers.google_auth.id_token.verify_oauth2_token", return_value=google_info(**info)):
            return self.client.post(SIGN_IN, {"id_token": token}, content_type="application/json", **KEY)

    def authed(self, email="pro@example.com", sub="sub-1"):
        response = self.sign_in(email=email, sub=sub)
        self.assertEqual(response.status_code, 200, response.content)
        return {**KEY, "HTTP_AUTHORIZATION": f"Bearer {response.json()['access']}"}

    def post_profile(self, headers, **overrides):
        return self.client.post(PROFILE, {**GOOD_PROFILE, **overrides}, content_type="application/json", **headers)

    def patch_profile(self, headers, **fields):
        return self.client.patch(PROFILE, fields, content_type="application/json", **headers)


# ---------------------------------------------------------------------------
class ProviderProfileModelTests(ProviderApiCase):
    def make(self, email="a@example.com", status=ProviderProfile.STATUS_PENDING):
        user = User.objects.create_user(username=email, email=email)
        profile = ProviderProfile.objects.create(
            user=user, business_name=email, phone="+17805550100", email=email, status=status
        )
        profile.categories.set(Service.objects.filter(slug="plumbing"))
        return profile

    def test_new_profiles_start_pending(self):
        self.assertEqual(self.make().status, ProviderProfile.STATUS_PENDING)

    def test_approving_and_rejecting_record_the_decision_and_when(self):
        profile = self.make()
        profile.approve()
        profile.refresh_from_db()
        self.assertEqual(profile.status, ProviderProfile.STATUS_APPROVED)
        self.assertIsNotNone(profile.reviewed_at)
        profile.reject("Licence number missing")
        profile.refresh_from_db()
        self.assertEqual((profile.status, profile.review_note), (ProviderProfile.STATUS_REJECTED, "Licence number missing"))

    def test_approved_returns_only_approved_profiles(self):
        pending, rejected = self.make("p@example.com"), self.make("r@example.com", ProviderProfile.STATUS_REJECTED)
        approved = self.make("ok@example.com", ProviderProfile.STATUS_APPROVED)
        self.assertEqual(list(ProviderProfile.objects.approved()), [approved])
        self.assertNotIn(pending, ProviderProfile.objects.approved())
        self.assertNotIn(rejected, ProviderProfile.objects.approved())


# ---------------------------------------------------------------------------
class GoogleSignInTests(ProviderApiCase):
    def test_a_new_provider_gets_an_account_and_tokens(self):
        response = self.sign_in()
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertTrue(body["is_new_account"])
        self.assertIsNone(body["profile"])
        self.assertEqual(body["email"], "pro@example.com")
        self.assertTrue(body["access"] and body["refresh"])

        user = User.objects.get(email="pro@example.com")
        self.assertEqual(user.profile.role, UserRole.PROVIDER)
        self.assertEqual(user.profile.full_name, "Pat Provider")
        self.assertFalse(user.has_usable_password())  # Google is the only way in
        self.assertEqual(GoogleIdentity.objects.get(user=user).sub, "sub-1")

    def test_signing_in_again_returns_the_same_account_and_its_profile(self):
        headers = self.authed()
        self.post_profile(headers)
        again = self.sign_in()
        self.assertFalse(again.json()["is_new_account"])
        self.assertEqual(User.objects.count(), 1)
        self.assertEqual(again.json()["profile"]["business_name"], "Ace Plumbing")
        self.assertEqual(again.json()["profile"]["status"], "pending")

    def test_the_issued_token_works_on_the_provider_endpoints(self):
        headers = self.authed()
        self.assertEqual(self.client.get(PROFILE, **headers).status_code, 404)  # signed in, not registered yet

    def test_the_google_account_id_wins_over_a_changed_email(self):
        self.sign_in(email="old@example.com", sub="sub-9")
        again = self.sign_in(email="new@example.com", sub="sub-9")
        self.assertEqual(again.status_code, 200)
        self.assertEqual(User.objects.count(), 1)
        self.assertEqual(again.json()["email"], "old@example.com")

    def test_an_existing_provider_account_with_that_email_is_linked(self):
        user = User.objects.create_user(username="pro@example.com", email="pro@example.com", password="x-pass-123")
        UserProfile.objects.create(user=user, role=UserRole.PROVIDER)
        response = self.sign_in(email="PRO@example.com")
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()["is_new_account"])
        self.assertEqual(GoogleIdentity.objects.get().user, user)
        self.assertEqual(User.objects.count(), 1)

    def test_a_client_account_with_that_email_is_never_taken_over(self):
        user = User.objects.create_user(username="pro@example.com", email="pro@example.com", password="x-pass-123")
        UserProfile.objects.create(user=user, role=UserRole.CUSTOMER)
        response = self.sign_in()
        self.assertEqual(response.status_code, 409)
        self.assertIn("client account", response.json()["detail"])
        self.assertEqual(GoogleIdentity.objects.count(), 0)
        self.assertNotIn("access", response.json())

    def test_a_disabled_account_cannot_sign_in(self):
        self.sign_in()
        User.objects.update(is_active=False)
        self.assertEqual(self.sign_in().status_code, 409)

    def test_the_token_must_be_for_this_app(self):
        with patch("providers.google_auth.id_token.verify_oauth2_token", return_value=google_info(aud="someone-elses-app")):
            response = self.client.post(SIGN_IN, {"id_token": "t"}, content_type="application/json", **KEY)
        self.assertEqual(response.status_code, 401)
        self.assertEqual(User.objects.count(), 0)

    def test_an_unverified_google_email_is_refused(self):
        with patch("providers.google_auth.id_token.verify_oauth2_token", return_value=google_info(email_verified=False)):
            response = self.client.post(SIGN_IN, {"id_token": "t"}, content_type="application/json", **KEY)
        self.assertEqual(response.status_code, 401)
        self.assertEqual(User.objects.count(), 0)

    def test_a_token_google_rejects_is_refused(self):
        with patch("providers.google_auth.id_token.verify_oauth2_token", side_effect=ValueError("Token expired")):
            response = self.client.post(SIGN_IN, {"id_token": "stale"}, content_type="application/json", **KEY)
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json(), {"detail": "That Google sign-in could not be verified."})

    def test_a_missing_or_blank_token_is_refused_without_calling_google(self):
        with patch("providers.google_auth.id_token.verify_oauth2_token") as verify:
            for body in ({}, {"id_token": ""}, {"id_token": "   "}, {"id_token": 5}, {"id_token": None}):
                response = self.client.post(SIGN_IN, body, content_type="application/json", **KEY)
                self.assertEqual(response.status_code, 401, body)
        verify.assert_not_called()

    @override_settings(GOOGLE_OAUTH_CLIENT_IDS=[])
    def test_without_a_configured_client_id_sign_in_is_unavailable(self):
        response = self.client.post(SIGN_IN, {"id_token": "t"}, content_type="application/json", **KEY)
        self.assertEqual(response.status_code, 503)

    def test_sign_in_attempts_are_rate_limited(self):
        with patch("providers.google_auth.id_token.verify_oauth2_token", side_effect=ValueError("bad")):
            codes = [
                self.client.post(SIGN_IN, {"id_token": "x"}, content_type="application/json", **KEY).status_code
                for _ in range(22)
            ]
        self.assertEqual(codes[:20], [401] * 20)
        self.assertEqual(codes[20:], [429, 429])

    def test_it_needs_the_api_key_and_only_accepts_post(self):
        response = self.client.post(SIGN_IN, {"id_token": "t"}, content_type="application/json")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json(), {"detail": "Missing or invalid API key."})
        self.assertEqual(self.client.get(SIGN_IN, **KEY).status_code, 405)


@override_settings(API_KEY=API_KEY, GOOGLE_OAUTH_CLIENT_IDS=[])
class DevFakeSignInTests(TestCase):
    def setUp(self):
        cache.clear()

    def sign_in(self, token="dev-fake:dev.provider@example.com"):
        return self.client.post(SIGN_IN, {"id_token": token}, content_type="application/json", **KEY)

    @override_settings(GOOGLE_DEV_FAKE_AUTH=True, DEBUG=True)
    def test_the_fake_token_works_only_with_the_flag_and_debug(self):
        response = self.sign_in()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["email"], "dev.provider@example.com")
        self.assertEqual(User.objects.get().profile.role, UserRole.PROVIDER)

    @override_settings(GOOGLE_DEV_FAKE_AUTH=False, DEBUG=True)
    def test_it_is_refused_when_the_flag_is_off(self):
        self.assertEqual(self.sign_in().status_code, 503)
        self.assertEqual(User.objects.count(), 0)

    @override_settings(GOOGLE_DEV_FAKE_AUTH=True, DEBUG=False)
    def test_it_is_refused_when_debug_is_off_even_with_the_flag(self):
        self.assertEqual(self.sign_in().status_code, 503)
        self.assertEqual(User.objects.count(), 0)

    @override_settings(GOOGLE_DEV_FAKE_AUTH=True, DEBUG=True)
    def test_a_fake_token_needs_an_email(self):
        self.assertEqual(self.sign_in("dev-fake:not-an-email").status_code, 401)

    def test_the_server_refuses_to_start_with_the_fake_login_outside_debug(self):
        with override_settings(GOOGLE_DEV_FAKE_AUTH=True, DEBUG=False):
            (error,) = check_dev_fake_auth()
        self.assertEqual(error.id, "providers.E001")
        for flag, debug in ((True, True), (False, True), (False, False)):
            with override_settings(GOOGLE_DEV_FAKE_AUTH=flag, DEBUG=debug):
                self.assertEqual(check_dev_fake_auth(), [], (flag, debug))


# ---------------------------------------------------------------------------
class RegisterAndEditProfileTests(ProviderApiCase):
    def test_registering_creates_a_pending_profile_with_a_normalised_phone(self):
        headers = self.authed()
        response = self.post_profile(headers)
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["status"], "pending")
        self.assertEqual(body["phone"], "+17805550100")
        self.assertEqual(sorted(body["categories"]), ["hvac", "plumbing"])
        self.assertEqual(body["cities"], ["Edmonton", "Calgary"])

        profile = ProviderProfile.objects.get()
        self.assertEqual(profile.user.email, "pro@example.com")
        self.assertEqual(profile.categories.count(), 2)

    def test_the_contact_email_defaults_to_the_google_email(self):
        headers = self.authed()
        data = {k: v for k, v in GOOD_PROFILE.items() if k != "email"}
        response = self.client.post(PROFILE, data, content_type="application/json", **headers)
        self.assertEqual(response.json()["email"], "pro@example.com")

    def test_upcoming_unlaunched_services_can_be_chosen(self):
        headers = self.authed()
        response = self.post_profile(headers, categories=["lawn-care"])
        self.assertEqual(response.status_code, 201)

    def test_status_and_review_fields_cannot_be_set_by_the_provider(self):
        headers = self.authed()
        response = self.post_profile(headers, status="approved", review_note="fine", reviewed_at="2026-01-01T00:00:00Z")
        self.assertEqual(response.status_code, 201)
        profile = ProviderProfile.objects.get()
        self.assertEqual((profile.status, profile.review_note, profile.reviewed_at), ("pending", "", None))

    def test_invalid_input_is_rejected_with_clear_messages(self):
        headers = self.authed()
        cases = {
            "business_name": "   ",
            "phone": "58792199587",
            "email": "not-an-email",
            "categories": [],
            "cities": [],
        }
        for field, value in cases.items():
            with self.subTest(field):
                response = self.post_profile(headers, **{field: value})
                self.assertEqual(response.status_code, 400)
                self.assertIn(field, response.json())
        self.assertEqual(self.post_profile(headers, phone="58792199587").json()["phone"][0],
                         "Enter a valid Canadian or North American phone number, for example 780 555 0100.")
        self.assertEqual(ProviderProfile.objects.count(), 0)

    def test_unknown_services_and_cities_are_rejected(self):
        headers = self.authed()
        self.assertEqual(self.post_profile(headers, categories=["not-a-service"]).status_code, 400)
        self.assertEqual(self.post_profile(headers, cities=["Atlantis"]).status_code, 400)
        Service.objects.filter(slug="plumbing").update(is_active=False)
        self.assertEqual(self.post_profile(headers, categories=["plumbing"]).status_code, 400)

    def test_the_four_cities_are_accepted_and_repeats_dropped(self):
        headers = self.authed()
        cities = ["Edmonton", "Calgary", "Fort McMurray", "Red Deer", "Edmonton"]
        response = self.post_profile(headers, cities=cities)
        self.assertEqual(response.json()["cities"], ["Edmonton", "Calgary", "Fort McMurray", "Red Deer"])

    def test_you_cannot_register_twice(self):
        headers = self.authed()
        self.post_profile(headers)
        self.assertEqual(self.post_profile(headers).status_code, 409)
        self.assertEqual(ProviderProfile.objects.count(), 1)

    def test_get_returns_my_profile_and_404_before_registering(self):
        headers = self.authed()
        self.assertEqual(self.client.get(PROFILE, **headers).status_code, 404)
        self.post_profile(headers)
        response = self.client.get(PROFILE, **headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["business_name"], "Ace Plumbing")

    def test_each_provider_only_sees_and_edits_their_own_profile(self):
        mine = self.authed("a@example.com", "sub-a")
        theirs = self.authed("b@example.com", "sub-b")
        self.post_profile(mine, business_name="Mine")
        self.post_profile(theirs, business_name="Theirs")
        self.patch_profile(mine, business_name="Mine edited")
        self.assertEqual(self.client.get(PROFILE, **mine).json()["business_name"], "Mine edited")
        self.assertEqual(self.client.get(PROFILE, **theirs).json()["business_name"], "Theirs")

    def test_patch_updates_only_the_fields_sent(self):
        headers = self.authed()
        self.post_profile(headers)
        response = self.patch_profile(headers, bio="New bio", cities=["Red Deer"], categories=["electrical"])
        self.assertEqual(response.status_code, 200)
        profile = ProviderProfile.objects.get()
        self.assertEqual((profile.bio, profile.cities, profile.business_name), ("New bio", ["Red Deer"], "Ace Plumbing"))
        self.assertEqual([s.slug for s in profile.categories.all()], ["electrical"])

    def test_patch_before_registering_is_a_404(self):
        self.assertEqual(self.patch_profile(self.authed(), bio="x").status_code, 404)

    def test_editing_an_approved_profile_keeps_it_approved(self):
        headers = self.authed()
        self.post_profile(headers)
        ProviderProfile.objects.get().approve()
        self.patch_profile(headers, bio="Updated")
        self.assertEqual(ProviderProfile.objects.get().status, "approved")

    def test_editing_a_rejected_profile_sends_it_back_for_review(self):
        headers = self.authed()
        self.post_profile(headers)
        ProviderProfile.objects.get().reject("Please add your licence")
        response = self.patch_profile(headers, bio="Added licence number 123")
        self.assertEqual(response.json()["status"], "pending")
        self.assertEqual(ProviderProfile.objects.get().status, "pending")

    def test_status_cannot_be_changed_by_a_patch(self):
        headers = self.authed()
        self.post_profile(headers)
        self.patch_profile(headers, status="approved")
        self.assertEqual(ProviderProfile.objects.get().status, "pending")

    def test_it_needs_a_login_the_api_key_and_a_provider_account(self):
        self.assertEqual(self.client.get(PROFILE, **KEY).status_code, 401)  # no token
        headers = self.authed()
        no_key = {"HTTP_AUTHORIZATION": headers["HTTP_AUTHORIZATION"]}
        self.assertEqual(self.client.get(PROFILE, **no_key).status_code, 403)  # valid token, no API key

        customer = User.objects.create_user(username="c@example.com", email="c@example.com", password="x-pass-123")
        UserProfile.objects.create(user=customer, role=UserRole.CUSTOMER)
        login = self.client.post(
            "/api/accounts/login/", {"email": "c@example.com", "password": "x-pass-123"},
            content_type="application/json", **KEY,
        )
        customer_headers = {**KEY, "HTTP_AUTHORIZATION": f"Bearer {login.json()['access']}"}
        self.assertEqual(self.client.get(PROFILE, **customer_headers).status_code, 403)
        self.assertEqual(self.post_profile(customer_headers).status_code, 403)


# ---------------------------------------------------------------------------
class MatchResultsTests(ProviderApiCase):
    def register(self, email, status, **profile):
        headers = self.authed(email, f"sub-{email}")
        self.post_profile(headers, business_name=email, **profile)
        provider = ProviderProfile.objects.get(user__email=email)
        provider.status = status
        provider.save(update_fields=["status"])
        return provider

    def matches(self, **params):
        return self.client.get(MATCHES, params, **KEY)

    def names(self, **params):
        return [r["business_name"] for r in self.matches(**params).json()["results"]]

    def test_only_approved_providers_appear(self):
        self.register("approved@example.com", "approved")
        self.register("pending@example.com", "pending")
        self.register("rejected@example.com", "rejected")
        self.assertEqual(self.names(category="plumbing"), ["approved@example.com"])

    def test_a_pending_provider_appears_once_approved_and_disappears_when_rejected(self):
        provider = self.register("pro@example.com", "pending")
        self.assertEqual(self.names(category="plumbing"), [])
        provider.approve()
        self.assertEqual(self.names(category="plumbing"), ["pro@example.com"])
        provider.reject()
        self.assertEqual(self.names(category="plumbing"), [])

    def test_results_are_filtered_by_service_and_city(self):
        self.register("both@example.com", "approved", categories=["plumbing", "hvac"], cities=["Edmonton", "Calgary"])
        self.register("calgary@example.com", "approved", categories=["plumbing"], cities=["Calgary"])
        self.register("electric@example.com", "approved", categories=["electrical"], cities=["Edmonton"])
        self.assertEqual(self.names(category="plumbing"), ["both@example.com", "calgary@example.com"])
        self.assertEqual(self.names(category="plumbing", city="Edmonton"), ["both@example.com"])
        self.assertEqual(self.names(category="plumbing", city="Red Deer"), [])
        self.assertEqual(self.names(category="hvac"), ["both@example.com"])
        self.assertEqual(self.names(category="glass-mirrors"), [])

    def test_clients_never_see_contact_details(self):
        self.register("pro@example.com", "approved")
        (result,) = self.matches(category="plumbing").json()["results"]
        self.assertEqual(set(result), {"id", "business_name", "bio", "categories", "cities"})
        self.assertNotIn("0100", str(result))
        self.assertNotIn("office@ace.example", str(result))

    def test_a_category_is_required_and_the_api_key_too(self):
        self.assertEqual(self.matches().status_code, 400)
        self.assertEqual(self.client.get(MATCHES, {"category": "plumbing"}).status_code, 401)

    def test_it_needs_no_login_so_the_client_flow_is_unchanged(self):
        self.assertEqual(self.matches(category="plumbing").status_code, 200)


# ---------------------------------------------------------------------------
class ProviderAdminTests(ProviderApiCase):
    def setUp(self):
        super().setUp()
        self.admin_user = User.objects.create_superuser("boss", "boss@example.com", "pw-for-tests-123")
        self.client.force_login(self.admin_user)
        headers = self.authed()
        self.post_profile(headers)
        self.profile = ProviderProfile.objects.get()

    def run_action(self, action):
        return self.client.post(
            "/admin/providers/providerprofile/", {"action": action, "_selected_action": [str(self.profile.pk)]}
        )

    def test_the_admin_action_approves_and_the_provider_then_appears_to_clients(self):
        self.assertEqual(self.client.get(MATCHES, {"category": "plumbing"}, **KEY).json()["results"], [])
        self.run_action("approve_selected")
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.status, "approved")
        self.assertIsNotNone(self.profile.reviewed_at)
        results = self.client.get(MATCHES, {"category": "plumbing"}, **KEY).json()["results"]
        self.assertEqual([r["business_name"] for r in results], ["Ace Plumbing"])

    def test_the_admin_action_rejects(self):
        self.run_action("reject_selected")
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.status, "rejected")
        self.assertEqual(self.client.get(MATCHES, {"category": "plumbing"}, **KEY).json()["results"], [])

    def test_the_provider_sees_the_decision_and_the_note(self):
        self.profile.reject("Please add your business licence")
        mine = self.client.get(PROFILE, **self.authed()).json()
        self.assertEqual((mine["status"], mine["review_note"]), ("rejected", "Please add your business licence"))

    def test_the_change_page_lists_everything_a_reviewer_needs(self):
        page = self.client.get(f"/admin/providers/providerprofile/{self.profile.pk}/change/")
        self.assertEqual(page.status_code, 200)
        for text in ("Ace Plumbing", "+17805550100", "office@ace.example", "Family-run since 2005."):
            self.assertContains(page, text)

    def test_the_list_offers_both_actions_and_needs_a_staff_login(self):
        page = self.client.get("/admin/providers/providerprofile/")
        self.assertContains(page, "Approve selected providers")
        self.assertContains(page, "Reject selected providers")
        self.client.logout()
        self.assertEqual(self.client.get("/admin/providers/providerprofile/").status_code, 302)
        self.run_action("approve_selected")
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.status, "pending")
