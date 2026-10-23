"""Seasonal reminders, run by the 15-minute cron job (leads.jobs.run_all).

While a campaign (growth.campaigns) is in season, each eligible past client
gets one push notification and one email about it, both opening the app's
request flow with the service chosen. Who is eligible:

  - an active client account that hasn't turned reminders off (Settings in
    the app, or the unsubscribe link in any reminder email);
  - who used the campaign's service, or one in its audience: a completed job
    in the last two years, or a request in the last six months. Those are
    CASL's implied-consent windows for an existing business relationship and
    an inquiry, so nobody else is ever emailed;
  - with no request for that service in the last 60 days (they've just dealt
    with it);
  - who has had no reminder this calendar month or in the last 30 days, and
    not this campaign already this season.

Sends happen only between 10:00 and 19:00 Edmonton time, at most
PER_RUN per run and SEASONAL_REMINDERS_DAILY_CAP a day, and only with
SEASONAL_REMINDERS_ENABLED on. Every send is logged as a ReminderSend.
"""

import logging
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.mail import EmailMessage
from django.db import IntegrityError, transaction
from django.db.models import Exists, OuterRef, Q
from django.utils import timezone

from accounts.models import UserRole
from catalog.models import Service
from catalog.taxonomy import launched_slugs
from leads.models import LeadOffer
from messaging import push
from provider_search.models import ServiceRequest
from provider_search.services import LAUNCHED_CITIES

from . import links
from .campaigns import active_campaigns
from .models import ReminderPreference, ReminderSend

logger = logging.getLogger(__name__)

LOCAL_TZ = ZoneInfo("America/Edmonton")
SEND_HOURS = (10, 19)
PER_RUN = 25
COMPLETED_JOB_WINDOW = timedelta(days=730)
INQUIRY_WINDOW = timedelta(days=183)
RECENT_REQUEST_WINDOW = timedelta(days=60)
MIN_GAP = timedelta(days=30)


def _local_day_start(local_now):
    return local_now.replace(hour=0, minute=0, second=0, microsecond=0)


def _used_services(now) -> dict[int, set[str]]:
    """client id -> the services they used recently enough to be reminded about (see the module docstring)."""
    completed = LeadOffer.objects.filter(
        service_request=OuterRef("pk"), job_completed=True, completed_at__gte=now - COMPLETED_JOB_WINDOW
    )
    rows = (
        ServiceRequest.objects.filter(
            user__isnull=False,
            user__is_active=True,
            user__profile__role=UserRole.CUSTOMER,
            city__in=LAUNCHED_CITIES,
        )
        .filter(Q(created_at__gte=now - INQUIRY_WINDOW) | Exists(completed))
        .values_list("user_id", "category")
    )
    used: dict[int, set[str]] = {}
    for user_id, category in rows:
        used.setdefault(user_id, set()).add(category)
    return used


def _email_body(user, campaign, service_name: str) -> str:
    request_url = settings.SITE_URL + links.open_request_path(campaign.service, "seasonal", campaign.slug)
    unsubscribe_url = settings.SITE_URL + links.unsubscribe_path(user)
    name = getattr(getattr(user, "profile", None), "full_name", "").split(" ")[0]
    lines = [
        f"Hi {name}," if name else "Hi,",
        "",
        campaign.email_body,
        "",
        f"Request {service_name} in the Tabmatch app (your request is filled in for you):",
        request_url,
        "",
        "--",
        f"You're getting this because you used Tabmatch for {service_name} or a related job.",
        f"To stop seasonal reminders: {unsubscribe_url}",
        "Or in the app: Settings > Seasonal reminders.",
        "",
        "Tabmatch",
        settings.BUSINESS_MAILING_ADDRESS,
    ]
    return "\n".join(lines)


def _send_email(user, campaign, service_name: str) -> bool:
    unsubscribe_url = settings.SITE_URL + links.unsubscribe_path(user)
    message = EmailMessage(
        subject=campaign.email_subject,
        body=_email_body(user, campaign, service_name),
        from_email=settings.DEFAULT_FROM_EMAIL,
        to=[user.email],
        # One-click unsubscribe from the mail app's own button (RFC 8058).
        headers={"List-Unsubscribe": f"<{unsubscribe_url}>", "List-Unsubscribe-Post": "List-Unsubscribe=One-Click"},
    )
    try:
        message.send()
    except Exception:  # noqa: BLE001 - logged; the caller stops this run
        logger.exception("Could not send seasonal reminder email (%s)", campaign.slug)
        return False
    return True


def send_seasonal_reminders(now=None) -> int:
    """Sends what is due this run. Returns how many clients were reminded."""
    if not settings.SEASONAL_REMINDERS_ENABLED:
        return 0
    now = now or timezone.now()
    local_now = now.astimezone(LOCAL_TZ)
    if not SEND_HOURS[0] <= local_now.hour < SEND_HOURS[1]:
        return 0
    campaigns = active_campaigns(local_now.month, launched_slugs())
    if not campaigns:
        return 0
    sent_today = ReminderSend.objects.filter(sent_at__gte=_local_day_start(local_now)).count()
    budget = min(PER_RUN, settings.SEASONAL_REMINDERS_DAILY_CAP - sent_today)
    if budget <= 0:
        return 0

    email_ready = bool(settings.SITE_URL and settings.BUSINESS_MAILING_ADDRESS)
    if not email_ready:
        logger.warning("SITE_URL or BUSINESS_MAILING_ADDRESS is not set: seasonal reminders go by push only")

    used = _used_services(now)
    month_start = _local_day_start(local_now).replace(day=1)
    recently_reminded = set(
        ReminderSend.objects.filter(sent_at__gte=min(month_start, now - MIN_GAP)).values_list("user_id", flat=True)
    )
    opted_out = set(ReminderPreference.objects.filter(seasonal_reminders=False).values_list("user_id", flat=True))
    already = set(
        ReminderSend.objects.filter(season_year=local_now.year, campaign__in=[c.slug for c in campaigns])
        .values_list("user_id", "campaign")
    )
    recent = set(
        ServiceRequest.objects.filter(created_at__gte=now - RECENT_REQUEST_WINDOW, user__isnull=False)
        .values_list("user_id", "category")
    )
    names = dict(Service.objects.values_list("slug", "name"))

    users = get_user_model().objects.select_related("profile").in_bulk(
        [u for u in used if u not in recently_reminded and u not in opted_out]
    )
    sent = 0
    for user_id in sorted(users):
        if sent >= budget:
            break
        user = users[user_id]
        services = used[user_id]

        def eligible(c):
            return (user_id, c.slug) not in already and (user_id, c.service) not in recent

        # A campaign for a service they actually used comes before one they "may need".
        choices = [c for c in campaigns if c.service in services and eligible(c)]
        choices += [c for c in campaigns if c not in choices and any(c.reaches(s) for s in services) and eligible(c)]
        if not choices:
            continue
        campaign = choices[0]
        service_name = names.get(campaign.service, campaign.service)

        # The log row goes in first: its unique constraint is what makes a second run (or an overlapping
        # one) skip this client and campaign.
        try:
            with transaction.atomic():
                log = ReminderSend.objects.create(
                    user=user, campaign=campaign.slug, service=campaign.service, season_year=local_now.year, sent_at=now
                )
        except IntegrityError:
            continue

        log.push_count = push.send_to_user(
            user,
            title=campaign.push_title,
            body=campaign.push_body,
            data={"type": "request_prefill", "service": campaign.service, "source": "seasonal", "ref": campaign.slug},
        )
        email_failed = False
        if email_ready and user.email:
            log.email_sent = _send_email(user, campaign, service_name)
            email_failed = not log.email_sent
        if not log.push_count and not log.email_sent:
            # Nothing reached them: forget the attempt so they can be reminded later.
            log.delete()
            if email_failed:
                break  # email is failing for everyone; try again next run
            continue
        if email_failed:
            log.note = "email failed"
        log.save(update_fields=["push_count", "email_sent", "note"])
        sent += 1
    return sent
