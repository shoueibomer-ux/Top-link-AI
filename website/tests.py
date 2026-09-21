from django.test import TestCase, override_settings

from catalog.models import Category, Service
from matching.matching_engine import CATEGORY_DISPLAY_NAMES, CATEGORY_TAXONOMY
from provider_search.chat_service import _CATEGORY_DISPLAY_NAMES
from provider_search.services import CATEGORY_QUERIES

from . import selectors
from .content.seo_pages import SEO_PAGES
from .models import Sector, SectorItem

PUBLIC_PATHS = ["/", "/sectors/", "/providers/", "/how-it-works/", "/get-the-app/"]


class PageTests(TestCase):
    def test_public_pages_render(self):
        for path in PUBLIC_PATHS:
            with self.subTest(path=path):
                self.assertEqual(self.client.get(path).status_code, 200)

    def test_home_has_required_copy_and_buttons(self):
        html = self.client.get("/").content.decode()
        self.assertIn(
            "Top-Link AI connects customers with trusted local service providers including "
            "electricians, plumbers, cleaners, contractors, and other professionals.",
            html,
        )
        self.assertIn("Find a Service", html)
        self.assertIn("Join as a Provider", html)

    def test_sectors_page_lists_every_sector_item_from_the_database(self):
        html = self.client.get("/sectors/").content.decode()
        for item in SectorItem.objects.all():
            self.assertIn(item.label.replace("&", "&amp;"), html)

    def test_seo_pages(self):
        self.assertEqual(
            set(SEO_PAGES),
            {"electrician-edmonton", "plumber-edmonton", "cleaning-service-edmonton",
             "contractor-edmonton", "home-improvement-edmonton"},
        )
        for slug, page in SEO_PAGES.items():
            with self.subTest(slug=slug):
                response = self.client.get(f"/{slug}/")
                self.assertEqual(response.status_code, 200)
                html = response.content.decode()
                self.assertIn(f"<title>{page['title']}</title>", html)
                self.assertIn(page["description"], html)
                self.assertIn('rel="canonical"', html)
                self.assertIn("application/ld+json", html)
                self.assertIn("How Top-Link AI works", html)
                self.assertIn("Request this service", html)
                self.assertLessEqual(len(page["title"]), 60)
                self.assertLessEqual(len(page["description"]), 160)

    def test_seo_pages_make_no_fake_claims(self):
        for slug in SEO_PAGES:
            html = self.client.get(f"/{slug}/").content.decode().lower()
            for banned in ("5-star", "★", "testimonial", "verified providers", "licensed and insured"):
                self.assertNotIn(banned, html)

    def test_service_detail_is_noindex(self):
        response = self.client.get("/services/landscaping/")
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'content="noindex,follow"')

    def test_logo_image_is_used_in_header_and_footer_and_files_exist(self):
        from django.contrib.staticfiles import finders

        html = self.client.get("/").content.decode()
        self.assertEqual(html.count("website/images/logo-roundel.png"), 2)  # header + footer
        self.assertNotIn(">TA<", html)
        for name in ("logo-roundel.png", "favicon-32.png", "favicon-48.png"):
            self.assertIsNotNone(finders.find(f"website/images/{name}"), name)
            self.assertIn(name.split(".")[0], html) if name.startswith("favicon") else None

    def test_unknown_service_404(self):
        self.assertEqual(self.client.get("/services/does-not-exist/").status_code, 404)

    def test_robots_and_sitemap(self):
        robots = self.client.get("/robots.txt").content.decode()
        self.assertIn("Disallow: /api/", robots)
        self.assertIn("/sitemap.xml", robots)
        sitemap = self.client.get("/sitemap.xml").content.decode()
        for slug in SEO_PAGES:
            self.assertIn(f"/{slug}/", sitemap)
        self.assertNotIn("/services/", sitemap)


class TaxonomyIntegrityTests(TestCase):
    def test_backend_counts(self):
        self.assertEqual(Category.objects.count(), 7)
        self.assertEqual(Service.objects.count(), 44)

    def test_sector_structure(self):
        self.assertEqual(Sector.objects.count(), 7)
        self.assertEqual(SectorItem.objects.count(), 36)

    def test_every_item_resolves_to_an_active_backend_service(self):
        for item in SectorItem.objects.select_related("service"):
            self.assertTrue(item.service.is_active, item.label)

    def test_landscaping_is_one_service_in_two_sectors(self):
        self.assertEqual(Service.objects.filter(slug="landscaping").count(), 1)
        sectors = set(
            SectorItem.objects.filter(service__slug="landscaping").values_list("sector__slug", flat=True)
        )
        self.assertEqual(sectors, {"home-services", "outdoor-services"})

    def test_every_service_is_covered_by_search_and_classification(self):
        slugs = set(Service.objects.values_list("slug", flat=True))
        for name, mapping in [
            ("CATEGORY_QUERIES", CATEGORY_QUERIES),
            ("CATEGORY_TAXONOMY", CATEGORY_TAXONOMY),
            ("CATEGORY_DISPLAY_NAMES", CATEGORY_DISPLAY_NAMES),
            ("chat display names", _CATEGORY_DISPLAY_NAMES),
        ]:
            self.assertEqual(slugs - set(mapping), set(), name)


@override_settings(API_KEY="test-key")
class ExistingRoutesStillWorkTests(TestCase):
    def test_admin_still_routes(self):
        self.assertEqual(self.client.get("/admin/").status_code, 302)

    def test_api_still_requires_key_and_serves_catalog(self):
        self.assertIn(self.client.get("/api/catalog/categories/").status_code, (401, 403))
        response = self.client.get("/api/catalog/categories/", HTTP_X_API_KEY="test-key")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()), 7)


class VisualIdentityTests(TestCase):
    def test_every_service_has_a_distinct_existing_icon(self):
        from .content.icons import SERVICE_ICONS
        from .icons import ICON_DIR

        slugs = set(Service.objects.values_list("slug", flat=True))
        self.assertEqual(slugs - set(SERVICE_ICONS), set())
        icons = [SERVICE_ICONS[s] for s in slugs]
        self.assertEqual(len(icons), len(set(icons)), "two services share an icon")
        for name in icons:
            self.assertTrue((ICON_DIR / f"{name}.svg").is_file(), name)

    def test_all_sectors_have_existing_icons(self):
        from .content.icons import SECTOR_ICONS
        from .icons import ICON_DIR

        for sector in Sector.objects.all():
            self.assertIn(sector.slug, SECTOR_ICONS)
            self.assertTrue((ICON_DIR / f"{SECTOR_ICONS[sector.slug]}.svg").is_file())

    def test_every_service_page_shows_its_icon_next_to_the_h1(self):
        for service in Service.objects.all():
            html = self.client.get(f"/services/{service.slug}/").content.decode()
            self.assertIn('class="title-row"', html, service.slug)
            self.assertRegex(html, r'icon-tile-hero">\s*<svg', service.slug)

    def test_home_has_hero_art_and_seven_sector_cards(self):
        html = self.client.get("/").content.decode()
        self.assertIn('class="hero-art"', html)
        self.assertEqual(html.count('class="sector-card"'), 7)

    def test_steps_use_distinct_icons(self):
        from .content.pages import HOW_IT_WORKS, JOURNEY_STEPS

        for steps in (HOW_IT_WORKS, JOURNEY_STEPS):
            icons = [step[-1] for step in steps]
            self.assertEqual(len(icons), len(set(icons)))

    def test_unknown_icon_falls_back_instead_of_failing(self):
        from .icons import render_icon

        self.assertIn("<svg", render_icon("does-not-exist"))


class StandardPagesTests(TestCase):
    def test_legal_and_contact_pages(self):
        for path in ("/contact/", "/privacy/", "/terms/"):
            response = self.client.get(path)
            self.assertEqual(response.status_code, 200, path)
        # draft legal pages stay out of search results until reviewed
        self.assertContains(self.client.get("/privacy/"), 'content="noindex,follow"')
        self.assertContains(self.client.get("/terms/"), 'content="noindex,follow"')
        self.assertContains(self.client.get("/privacy/"), "Draft.")

    def test_footer_links_to_legal_pages(self):
        html = self.client.get("/").content.decode()
        for path in ("/contact/", "/privacy/", "/terms/"):
            self.assertIn(f'href="{path}"', html)

    def test_branded_404_for_website_paths(self):
        response = self.client.get("/definitely-not-a-page/")
        self.assertEqual(response.status_code, 404)
        self.assertIn("find that page", response.content.decode())
        self.assertIn('content="noindex,follow"', response.content.decode())

    def test_unmatched_api_path_returns_json_404(self):
        response = self.client.get("/api/does-not-exist/")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response["Content-Type"], "application/json")

    def test_500_template_renders_without_the_database(self):
        from django.template.loader import render_to_string

        self.assertIn("Something went wrong", render_to_string("500.html"))


class LinkIntegrityTests(TestCase):
    def test_every_internal_link_resolves(self):
        from .linkcheck import crawl

        result = crawl(self.client)
        reached = set(result["pages"])
        expected = {"/", "/sectors/", "/providers/", "/how-it-works/", "/contact/", "/privacy/", "/terms/", "/get-the-app/"}
        expected |= {f"/{slug}/" for slug in SEO_PAGES}
        expected |= {item_url for item_url in (
            selectors.service_url(i.service.slug) for i in SectorItem.objects.select_related("service"))}
        self.assertEqual(expected - reached, set(), "pages that should be reachable from the site were not")
        self.assertEqual(result["broken"], [], result["broken"])
