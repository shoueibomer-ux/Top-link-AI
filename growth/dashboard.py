"""Numbers for the admin's growth dashboard (growth.admin.GrowthReportAdmin):
requests per week by source, and how many of them got an accepted offer and
a completed job. Weeks start on Monday, Edmonton time."""

from collections import Counter, defaultdict
from datetime import timedelta
from zoneinfo import ZoneInfo

from django.db.models import Count, Exists, OuterRef
from django.db.models.functions import TruncWeek
from django.utils import timezone

from leads.models import LeadOffer
from provider_search.models import ServiceRequest

from .models import InviteSignup, ReminderPreference, ReminderSend

LOCAL_TZ = ZoneInfo("America/Edmonton")
SOURCES = ServiceRequest.SOURCE_CHOICES


def _week_start(local_dt):
    day = local_dt.replace(hour=0, minute=0, second=0, microsecond=0)
    return day - timedelta(days=day.weekday())


def _cell(requests: int, accepted: int, completed: int) -> dict:
    return {
        "requests": requests,
        "accepted": accepted,
        "completed": completed,
        "accepted_rate": round(accepted / requests * 100) if requests else None,
        "completed_rate": round(completed / requests * 100) if requests else None,
    }


def _by_week(queryset, field: str) -> Counter:
    rows = queryset.annotate(week=TruncWeek(field, tzinfo=LOCAL_TZ)).values("week").annotate(n=Count("id"))
    return Counter({row["week"].date(): row["n"] for row in rows})


def weekly_report(weeks: int = 12, now=None) -> dict:
    now = now or timezone.now()
    first_week = _week_start(now.astimezone(LOCAL_TZ)) - timedelta(weeks=weeks - 1)
    week_starts = [(first_week + timedelta(weeks=i)).date() for i in range(weeks)]

    requests = (
        ServiceRequest.objects.filter(created_at__gte=first_week)
        .annotate(
            week=TruncWeek("created_at", tzinfo=LOCAL_TZ),
            accepted=Exists(LeadOffer.objects.filter(service_request=OuterRef("pk"), status=LeadOffer.STATUS_ACCEPTED)),
            completed=Exists(LeadOffer.objects.filter(service_request=OuterRef("pk"), job_completed=True)),
        )
        .values_list("week", "source", "source_ref", "accepted", "completed")
    )
    tally = defaultdict(lambda: [0, 0, 0])  # (week, source) -> [requests, accepted, completed]
    refs = defaultdict(Counter)  # source -> ref -> requests
    for week, source, ref, accepted, completed in requests:
        for key in ((week.date(), source), (week.date(), "all"), ("total", source), ("total", "all")):
            counts = tally[key]
            counts[0] += 1
            counts[1] += int(accepted)
            counts[2] += int(completed)
        if ref:
            refs[source][ref] += 1

    signups = _by_week(InviteSignup.objects.filter(created_at__gte=first_week), "created_at")
    reminders = _by_week(ReminderSend.objects.filter(sent_at__gte=first_week), "sent_at")
    opt_outs = _by_week(
        ReminderPreference.objects.filter(seasonal_reminders=False, updated_at__gte=first_week), "updated_at"
    )

    columns = [*SOURCES, ("all", "All")]
    rows = [
        {
            "week": week,
            "cells": [_cell(*tally[(week, key)]) for key, _ in columns],
            "invite_signups": signups[week],
            "reminders_sent": reminders[week],
            "reminder_opt_outs": opt_outs[week],
        }
        for week in reversed(week_starts)
    ]
    return {
        "columns": [label for _, label in columns],
        "rows": rows,
        "totals": [_cell(*tally[("total", key)]) for key, _ in columns],
        "totals_extra": {
            "invite_signups": sum(signups.values()),
            "reminders_sent": sum(reminders.values()),
            "reminder_opt_outs": sum(opt_outs.values()),
        },
        "top_refs": [
            {"label": label, "refs": refs[key].most_common(10)} for key, label in SOURCES if refs[key]
        ],
        "weeks": weeks,
    }
