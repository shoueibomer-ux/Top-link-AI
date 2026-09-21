from django.core.management.base import BaseCommand, CommandError
from django.test import Client
from django.test.utils import setup_test_environment

from website.linkcheck import crawl


class Command(BaseCommand):
    help = "Crawl the website from / and report any broken internal links."

    def handle(self, *args, **options):
        setup_test_environment()  # allows the 'testserver' host for the crawl
        result = crawl(Client())
        self.stdout.write(f"pages crawled:        {len(result['pages'])}")
        self.stdout.write(f"internal links checked: {result['links_checked']}")
        self.stdout.write(f"external links skipped: {result['external_skipped']}")
        if result["broken"]:
            for source, url, why in result["broken"]:
                self.stderr.write(f"BROKEN  {source}  ->  {url}   [{why}]")
            raise CommandError(f"{len(result['broken'])} broken link(s)")
        self.stdout.write(self.style.SUCCESS("No broken internal links."))
