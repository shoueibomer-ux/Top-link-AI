"""Removing chat photos from the private R2 bucket once the person or conversation they belong to is gone."""

import logging

from . import storage
from .models import PhotoDeletion

logger = logging.getLogger(__name__)


def queue_photos(keys) -> None:
    """Remember these photos must be deleted. Safe to call twice for the same key."""
    PhotoDeletion.objects.bulk_create([PhotoDeletion(key=k) for k in set(keys) if k], ignore_conflicts=True)


def purge(keys=None) -> tuple[int, int]:
    """Delete the queued photos (all of them, or just `keys`) from the bucket. Returns (deleted, still_waiting).
    Without R2 configured nothing can be reached, so they stay queued rather than being forgotten."""
    queued = PhotoDeletion.objects.all()
    if keys is not None:
        queued = queued.filter(key__in=list(keys))
    items = list(queued)
    if not items:
        return 0, 0
    if not storage.configured():
        return 0, len(items)
    deleted = 0
    for item in items:
        try:
            storage.delete(item.key)
        except Exception as exc:  # noqa: BLE001 - any failure means "try again later"
            PhotoDeletion.objects.filter(pk=item.pk).update(attempts=item.attempts + 1, last_error=type(exc).__name__)
            logger.warning("Could not delete a chat photo from storage (%s); it stays queued", type(exc).__name__)
            continue
        PhotoDeletion.objects.filter(pk=item.pk).delete()
        deleted += 1
    return deleted, len(items) - deleted
