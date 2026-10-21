from django.core.management.base import BaseCommand

from messaging import photo_queue, storage


class Command(BaseCommand):
    help = (
        "Deletes chat photos from the private bucket that belong to deleted accounts or conversations "
        "(the ones a failed delete left behind). Safe to run any time, and to run on a schedule."
    )

    def handle(self, *args, **options):
        if not storage.configured():
            self.stdout.write(self.style.WARNING("R2 is not configured here, so nothing can be deleted. Run this on Render."))
        deleted, waiting = photo_queue.purge()
        self.stdout.write(f"Deleted {deleted} photo(s); {waiting} still queued.")
