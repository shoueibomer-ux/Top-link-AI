"""A read-only inventory of every kind of "provider" the app stores, to plan
merging them into one model. Nothing here writes: it only counts and reads,
and read_only_guard() turns any attempted write into an error."""

import re
from collections import Counter, defaultdict
from contextlib import contextmanager

from django.contrib.auth import get_user_model
from django.db import connection

from accounts.models import ProviderBusinessProfile, UserProfile, UserRole
from catalog.models import Service
from leads.models import LeadOffer
from leads.models import Provider as ManualProvider
from leads.phone import normalize_north_american_phone, normalize_phone
from matching.models import Profile as MatchingProfile
from provider_search.models import ProviderOnboarding
from provider_search.services import CITIES

from .models import GoogleIdentity, ProviderProfile

User = get_user_model()

_WRITE_STATEMENT = re.compile(r"^\s*(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|REPLACE)\b", re.IGNORECASE)


class WriteAttempted(RuntimeError):
    pass


@contextmanager
def read_only_guard():
    """Any SQL that would change data raises WriteAttempted instead of running."""

    def refuse(execute, sql, params, many, context):
        if _WRITE_STATEMENT.match(sql):
            raise WriteAttempted(f"The audit tried to run a write: {sql[:60]}")
        return execute(sql, params, many, context)

    with connection.execute_wrapper(refuse):
        yield


# ---- masking: the report is for planning, not for spreading contact details ----

def mask_phone(raw: str) -> str:
    number = normalize_phone(raw) or (raw or "").strip()
    return f"{number[:5]}***{number[-4:]}" if len(number) >= 10 else "***"


def mask_email(raw: str) -> str:
    local, _, domain = (raw or "").partition("@")
    return f"{local[:1]}***@{domain}" if domain else "***"


# ---- the report ---------------------------------------------------------------

def _by_status(queryset, statuses):
    counts = {status: 0 for status in statuses}
    for row in queryset.values("status").order_by().annotate(n=_count()):
        counts[row["status"]] = row["n"]
    return counts


def _count():
    from django.db.models import Count

    return Count("id")


def _phone_problems(label_ids):
    """(unreadable, readable-but-not-North-American) id lists for (id, phone) pairs."""
    unreadable, other_country = [], []
    for pk, phone in label_ids:
        if not (phone or "").strip():
            continue
        if not normalize_phone(phone):
            unreadable.append(pk)
        elif not normalize_north_american_phone(phone):
            other_country.append(pk)
    return sorted(unreadable), sorted(other_country)


def build_report(show_details: bool = False) -> dict:
    phone_text = (lambda value: normalize_phone(value) or value) if show_details else mask_phone
    email_text = (lambda value: value) if show_details else mask_email

    known_slugs = set(Service.objects.values_list("slug", flat=True))

    # --- leads.Provider: businesses added by hand ---------------------------------
    manual = list(ManualProvider.objects.prefetch_related("services"))
    manual_unreadable, manual_other = _phone_problems((p.pk, p.phone) for p in manual)
    manual_stats = {
        "total": len(manual),
        "active": sum(p.is_active for p in manual),
        "sms_opt_out": sum(p.sms_opt_out for p in manual),
        "sms_consent_confirmed": sum(p.sms_consent_confirmed for p in manual),
        "no_services": sum(1 for p in manual if not p.services.all()),
        "no_service_areas": sum(1 for p in manual if not (p.service_areas or [])),
        "unreadable_phone_ids": manual_unreadable,
        "non_north_american_phone_ids": manual_other,
    }

    # --- lead offers --------------------------------------------------------------
    offers = LeadOffer.objects.all()
    offer_stats = {
        "total": offers.count(),
        "by_status": _by_status(offers, [s for s, _ in LeadOffer.STATUS_CHOICES]),
        "awaiting_reply": offers.filter(
            status__in=[LeadOffer.STATUS_SENT, LeadOffer.STATUS_VIEWED], responded_at__isnull=True
        ).count(),
        "created_but_never_sent": offers.filter(status=LeadOffer.STATUS_PENDING).count(),
        "hired": offers.filter(hired=True).count(),
        "providers_with_offers": offers.values("provider").distinct().count(),
    }

    # --- accounts ------------------------------------------------------------------
    roles = Counter(UserProfile.objects.values_list("role", flat=True))
    account_stats = {
        "provider_accounts": roles[UserRole.PROVIDER],
        "customer_accounts": roles[UserRole.CUSTOMER],
        "admin_accounts": roles[UserRole.ADMIN],
        "provider_accounts_without_any_profile": UserProfile.objects.filter(
            role=UserRole.PROVIDER,
            user__provider_business_profile__isnull=True,
            user__registered_provider__isnull=True,
        ).count(),
    }

    # --- accounts.ProviderBusinessProfile: email/password providers ----------------
    business = list(ProviderBusinessProfile.objects.select_related("user"))
    business_unreadable, business_other = _phone_problems((p.pk, p.phone) for p in business)
    unknown_categories = Counter(
        slug for p in business for slug in (p.categories or []) if slug not in known_slugs
    )
    unknown_cities = Counter(p.city for p in business if p.city and p.city not in CITIES)
    business_stats = {
        "total": len(business),
        "empty_business_name": sum(1 for p in business if not p.business_name.strip()),
        "with_phone": sum(1 for p in business if p.phone.strip()),
        "with_city": sum(1 for p in business if p.city),
        "with_categories": sum(1 for p in business if p.categories),
        "claimed_a_google_places_listing": sum(1 for p in business if p.place_id),
        "unreadable_phone_ids": business_unreadable,
        "non_north_american_phone_ids": business_other,
        "categories_not_in_catalog": dict(unknown_categories),
        "cities_not_in_the_four": dict(unknown_cities),
    }

    # --- providers.ProviderProfile: Google sign-in providers ------------------------
    google = list(ProviderProfile.objects.select_related("user"))
    google_unreadable, google_other = _phone_problems((p.pk, p.phone) for p in google)
    google_stats = {
        "total": len(google),
        "by_status": _by_status(ProviderProfile.objects.all(), [s for s, _ in ProviderProfile.STATUS_CHOICES]),
        "with_google_identity": GoogleIdentity.objects.count(),
        "unreadable_phone_ids": google_unreadable,
        "non_north_american_phone_ids": google_other,
        "cities_not_in_the_four": dict(Counter(c for p in google for c in (p.cities or []) if c not in CITIES)),
    }

    # --- the other provider-ish things that are not part of the merge -------------------
    onboarding = list(ProviderOnboarding.objects.all())
    other_stats = {
        "provider_onboarding_demo_total": len(onboarding),
        "provider_onboarding_demo_complete": sum(1 for o in onboarding if o.is_complete),
        "matching_profile_prototype_total": MatchingProfile.objects.count(),
    }

    # --- people who appear more than once --------------------------------------------------
    # (label, user id or None, phone, email)
    records = (
        [(f"leads.Provider#{p.pk}", None, p.phone, "") for p in manual]
        + [(f"accounts.ProviderBusinessProfile#{p.pk}", p.user_id, p.phone, p.user.email) for p in business]
        + [(f"providers.ProviderProfile#{p.pk}", p.user_id, p.phone, p.email) for p in google]
        + [(f"providers.ProviderProfile#{p.pk}", p.user_id, "", p.user.email) for p in google]
    )
    index = defaultdict(lambda: {"labels": set(), "users": set()})
    for label, user_id, phone, email in records:
        keys = []
        if normalize_phone(phone):
            keys.append(("phone", normalize_phone(phone)))
        if (email or "").strip():
            keys.append(("email", email.strip().lower()))
        for key in keys:
            index[key]["labels"].add(label)
            index[key]["users"].add(user_id)
    duplicates = []
    for (kind, value), entry in sorted(index.items()):
        if len(entry["labels"]) < 2:
            continue
        same_account = len(entry["users"]) == 1 and None not in entry["users"]
        shown = phone_text(value) if kind == "phone" else email_text(value)
        duplicates.append({
            "matched_on": f"{kind}: {shown}",
            "records": sorted(entry["labels"]),
            "same_account": same_account,
        })

    both = sorted(
        User.objects.filter(provider_business_profile__isnull=False, registered_provider__isnull=False)
        .values_list("id", flat=True)
    )

    report = {
        "read_only": True,
        "leads_provider": manual_stats,
        "lead_offers": offer_stats,
        "accounts": account_stats,
        "business_profiles": business_stats,
        "provider_profiles": google_stats,
        "not_part_of_the_merge": other_stats,
        "duplicates": duplicates,
        "users_with_both_a_business_profile_and_a_provider_profile": both,
    }
    report["notes"] = _notes(report)
    return report


def _notes(report: dict) -> list:
    """What to deal with before or during the merge, most important first."""
    notes = []

    def add(level, text):
        notes.append({"level": level, "text": text})

    offers = report["lead_offers"]
    if offers["awaiting_reply"]:
        add("blocker", f"{offers['awaiting_reply']} lead offer(s) are still awaiting a provider's reply. Repointing "
            "offers to the new model should wait until they are answered or expired.")
    if offers["created_but_never_sent"]:
        add("warning", f"{offers['created_but_never_sent']} lead offer(s) were created but never sent.")

    manual = report["leads_provider"]
    if manual["unreadable_phone_ids"]:
        add("warning", f"{len(manual['unreadable_phone_ids'])} hand-added provider(s) have a phone number that can't be "
            f"read (leads.Provider ids {manual['unreadable_phone_ids']}). Their SMS replies could never be matched.")
    if manual["non_north_american_phone_ids"]:
        add("note", f"{len(manual['non_north_american_phone_ids'])} hand-added provider(s) have a non-North-American "
            "number, so the new model's phone rule must allow that for manual providers.")
    if manual["sms_opt_out"]:
        add("note", f"{manual['sms_opt_out']} hand-added provider(s) have opted out of SMS. That must carry over: "
            "opt-out always wins when records are merged.")
    unconsented = manual["total"] - manual["sms_consent_confirmed"]
    if unconsented:
        add("note", f"{unconsented} hand-added provider(s) have no SMS consent recorded, so they can't be sent offers yet.")

    business = report["business_profiles"]
    if business["categories_not_in_catalog"]:
        add("warning", "Email/password provider profiles use services that aren't in the catalog and can't be mapped: "
            f"{business['categories_not_in_catalog']}.")
    if business["cities_not_in_the_four"]:
        add("warning", f"Email/password provider profiles use cities outside the four: {business['cities_not_in_the_four']}.")
    if business["unreadable_phone_ids"] or business["non_north_american_phone_ids"]:
        bad = len(business["unreadable_phone_ids"]) + len(business["non_north_american_phone_ids"])
        add("warning", f"{bad} email/password provider profile(s) have a phone number that isn't a North American number.")
    if business["total"]:
        add("note", f"{business['total']} email/password provider profile(s) would start as pending review.")
    if business["claimed_a_google_places_listing"]:
        add("note", f"{business['claimed_a_google_places_listing']} profile(s) claimed a Google Places listing, a feature "
            "that no longer exists; the claim would be dropped.")

    accounts = report["accounts"]
    if accounts["provider_accounts_without_any_profile"]:
        add("note", f"{accounts['provider_accounts_without_any_profile']} provider account(s) have no profile of any kind.")

    possible = [d for d in report["duplicates"] if not d["same_account"]]
    if possible:
        add("warning", f"{len(possible)} phone number(s) or email(s) appear on records of different people/accounts; "
            "each needs a decision on whether they are the same provider.")
    if report["users_with_both_a_business_profile_and_a_provider_profile"]:
        add("note", f"{len(report['users_with_both_a_business_profile_and_a_provider_profile'])} account(s) have both an "
            "email/password profile and a Google profile; they merge into one.")

    order = {"blocker": 0, "warning": 1, "note": 2}
    return sorted(notes, key=lambda n: order[n["level"]])
