"""The one place that answers "which service slugs exist?" for classification
and request validation. Everything keys on catalog.Service.slug."""

from .models import Service


def _live_services():
    return Service.objects.filter(is_active=True, category__is_active=True)


def active_service_names() -> dict:
    """{slug: display name} for every active service — what the classifiers
    may return, launched or not."""
    return dict(_live_services().values_list("slug", "name"))


def launched_slugs() -> set:
    """Slugs of active services we can actually serve right now."""
    return set(_live_services().filter(is_launched=True).values_list("slug", flat=True))
