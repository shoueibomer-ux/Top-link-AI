"""What the Render cron job runs every 15 minutes (see run_lead_jobs): nudge
slow providers, expire stale offers, email you when a request has no YES, and
send the daily summary. All of it is plain queries over LeadOffer — no queue,
no agents."""

import logging
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.conf import settings
from django.core.mail import send_mail
from django.db.models import Avg, Count, Min, Q
from django.utils import timezone

from catalog.models import Service
from provider_search.models import ServiceRequest

from . import services, sms
from .models import DailySummaryLog, LeadOffer

logger = logging.getLogger(__name__)

REMINDER_AFTER = timedelta(minutes=30)
NO_YES_ALERT_AFTER = timedelta(hours=2)
OFFER_EXPIRES_AFTER = timedelta(hours=24)
SUMMARY_HOUR_UTC = 14  # 7-8am in Edmonton
QUIET_HOURS = (21, 8)  # no automatic texts from 21:00 to 08:00 Edmonton time
LOCAL_TZ = ZoneInfo("America/Edmonton")


def in_quiet_hours(now) -> bool:
    start, end = QUIET_HOURS
    hour = now.astimezone(LOCAL_TZ).hour
    return hour >= start or hour < end


def notify_admin(subject: str, body: str) -> bool:
    """Emails ADMIN_ALERT_EMAIL. Returns False (and logs) if that isn't set or
    sending fails, so callers retry on the next run instead of losing it."""
    if not settings.ADMIN_ALERT_EMAIL:
        logger.warning("ADMIN_ALERT_EMAIL is not set; not sending: %s", subject)
        return False
    try:
        send_mail(subject, body, settings.DEFAULT_FROM_EMAIL, [settings.ADMIN_ALERT_EMAIL])
    except Exception:
        logger.exception("Could not send admin email: %s", subject)
        return False
    return True


def send_reminders(now=None) -> int:
    """One SMS reminder to providers who haven't answered 30 minutes after the
    offer was sent. Only with SMS on, never in quiet hours, never twice."""
    now = now or timezone.now()
    if not sms.sms_enabled() or in_quiet_hours(now):
        return 0
    due = LeadOffer.objects.filter(
        status=LeadOffer.STATUS_SENT,
        sent_at__lte=now - REMINDER_AFTER,
        reminder_sent_at__isnull=True,
        provider__sms_opt_out=False,
    ).select_related("provider", "service_request")
    sent = 0
    for offer in due:
        try:
            sms.send_sms(offer.provider.phone, services.reminder_message(offer))
        except sms.SmsOptedOut:
            offer.provider.sms_opt_out = True
            offer.provider.save(update_fields=["sms_opt_out"])
            continue
        except sms.SmsError as exc:
            logger.warning("Reminder for offer %s failed: %s", offer.pk, exc)
            continue
        offer.reminder_sent_at = now
        offer.save(update_fields=["reminder_sent_at"])
        sent += 1
    return sent


def expire_offers(now=None) -> int:
    now = now or timezone.now()
    return LeadOffer.objects.filter(
        status__in=[LeadOffer.STATUS_SENT, LeadOffer.STATUS_VIEWED],
        sent_at__lte=now - OFFER_EXPIRES_AFTER,
    ).update(status=LeadOffer.STATUS_EXPIRED)


def alert_requests_without_yes(now=None) -> int:
    """Emails you once per request that still has no YES two hours after its
    first offer was sent."""
    now = now or timezone.now()
    stale = (
        ServiceRequest.objects.filter(no_yes_alert_sent_at__isnull=True)
        .annotate(
            first_sent=Min("offers__sent_at"),
            accepted=Count("offers", filter=Q(offers__status=LeadOffer.STATUS_ACCEPTED)),
        )
        .filter(first_sent__lte=now - NO_YES_ALERT_AFTER, accepted=0)
    )
    alerted = 0
    for request in stale:
        lines = [
            f"Request #{request.pk}: {services.service_name(request)} in {request.city} "
            f"({services.urgency_label(request)}) has no YES yet.",
            f"First offer sent {request.first_sent:%Y-%m-%d %H:%M} UTC. Offers:",
        ]
        for offer in request.offers.select_related("provider"):
            lines.append(f"  - {offer.provider}: {offer.get_status_display()}")
        if notify_admin(f"No YES yet: request #{request.pk} ({services.service_name(request)})", "\n".join(lines)):
            ServiceRequest.objects.filter(pk=request.pk).update(no_yes_alert_sent_at=now)
            alerted += 1
    return alerted


def build_daily_summary(now=None) -> str:
    """Numbers for the 24 hours up to `now`."""
    now = now or timezone.now()
    since = now - timedelta(hours=24)

    new_requests = ServiceRequest.objects.filter(created_at__gte=since)
    waitlisted = new_requests.filter(status=ServiceRequest.STATUS_WAITLISTED).count()
    sent = LeadOffer.objects.filter(sent_at__gte=since)
    sent_count = sent.count()
    answered = sent.filter(status__in=[LeadOffer.STATUS_ACCEPTED, LeadOffer.STATUS_DECLINED]).count()
    replies = LeadOffer.objects.filter(
        responded_at__gte=since, status__in=[LeadOffer.STATUS_ACCEPTED, LeadOffer.STATUS_DECLINED]
    )
    average = replies.aggregate(avg=Avg("response_time"))["avg"]
    yes_count = LeadOffer.objects.filter(status=LeadOffer.STATUS_ACCEPTED, responded_at__gte=since).count()
    hired_count = LeadOffer.objects.filter(hired=True, hired_at__gte=since).count()

    rate = f"{answered / sent_count:.0%} ({answered} of {sent_count})" if sent_count else "n/a (no offers sent)"
    if average is None:
        average_text = "n/a (no replies)"
    else:
        minutes = round(average.total_seconds() / 60)
        average_text = f"{minutes} min"

    top_waitlist = (
        new_requests.filter(status=ServiceRequest.STATUS_WAITLISTED)
        .values("category")
        .annotate(n=Count("id"))
        .order_by("-n")[:3]
    )
    names = dict(Service.objects.values_list("slug", "name"))
    waitlist_line = ", ".join(f"{names.get(row['category'], row['category'])} ({row['n']})" for row in top_waitlist)

    lines = [
        f"Tabmatch daily summary, last 24 hours to {now:%Y-%m-%d %H:%M} UTC",
        "",
        f"New requests:          {new_requests.count()} ({waitlisted} waitlisted)",
        f"Offers sent:           {sent_count}",
        f"Response rate:         {rate}",
        f"Average response time: {average_text}",
        f"YES replies:           {yes_count}",
        f"Hired:                 {hired_count}",
    ]
    if waitlist_line:
        lines += ["", f"Most waitlisted: {waitlist_line}"]
    return "\n".join(lines)


def send_daily_summary_if_due(now=None) -> bool:
    """Sends the summary once a day, on the first run at or after 14:00 UTC."""
    now = now or timezone.now()
    today = now.date()
    if now.hour < SUMMARY_HOUR_UTC or DailySummaryLog.objects.filter(date=today).exists():
        return False
    if not notify_admin(f"Tabmatch daily summary {today}", build_daily_summary(now)):
        return False
    DailySummaryLog.objects.get_or_create(date=today)
    return True


def run_all(now=None) -> dict:
    now = now or timezone.now()
    return {
        "reminders_sent": send_reminders(now),
        "offers_expired": expire_offers(now),
        "no_yes_alerts": alert_requests_without_yes(now),
        "daily_summary_sent": send_daily_summary_if_due(now),
    }
