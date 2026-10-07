from django.core.management.base import BaseCommand

from leads import jobs


class Command(BaseCommand):
    help = (
        "Run by the Render cron job every 15 minutes: remind slow providers (only when SMS_ENABLED), "
        "expire stale offers, email when a request has no YES after 2 hours, and send the daily summary."
    )

    def handle(self, *args, **options):
        for name, result in jobs.run_all().items():
            self.stdout.write(f"{name}: {result}")
