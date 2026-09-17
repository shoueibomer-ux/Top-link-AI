from django.core.management.base import BaseCommand

from provider_search.services import CATEGORY_QUERIES, CITIES, search_providers


class Command(BaseCommand):
    help = (
        "Force-refreshes the cached Google Places results for every "
        "category x city pair. Intended to run monthly via cron, ahead of "
        "the 35-day cache expiry, so the cache never actually goes cold."
    )

    def handle(self, *args, **options):
        total_providers = 0
        failures = 0

        for category in CATEGORY_QUERIES:
            for city in CITIES:
                try:
                    providers = search_providers(category, city, force_refresh=True)
                except Exception as exc:  # keep going — one bad pair shouldn't abort the rest
                    failures += 1
                    self.stderr.write(self.style.ERROR(f"{category} / {city}: {exc}"))
                    continue

                total_providers += len(providers)
                self.stdout.write(self.style.SUCCESS(f"{category} / {city}: refreshed {len(providers)} providers"))

        summary = f"Done. {total_providers} provider records refreshed across {len(CATEGORY_QUERIES) * len(CITIES)} category/city pairs."
        if failures:
            summary += f" {failures} pair(s) failed — see errors above."
        self.stdout.write(self.style.SUCCESS(summary))
