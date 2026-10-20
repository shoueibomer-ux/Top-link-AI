"""A provider's rating: the average and the number of reviews, counting only reviews that are not hidden."""

from django.db.models import Avg, Count

from .models import Review


EMPTY = {"rating_average": None, "review_count": 0}


def _shape(average, count) -> dict:
    return {"rating_average": round(float(average), 1) if count and average is not None else None, "review_count": count or 0}


def summaries(provider_ids) -> dict:
    """{provider_id: {"rating_average": 4.5 | None, "review_count": n}} for each id, in one query."""
    ids = list(set(provider_ids))
    found = {
        row["provider_id"]: row
        for row in Review.objects.filter(provider_id__in=ids, hidden=False)
        .values("provider_id")
        .annotate(avg=Avg("rating"), n=Count("id"))
        .order_by()
    }
    return {pid: _shape(found[pid]["avg"], found[pid]["n"]) if pid in found else _shape(None, 0) for pid in ids}


def summary_for(provider_id) -> dict:
    return summaries([provider_id])[provider_id]
