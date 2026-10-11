from django.test import TestCase, override_settings

from catalog.models import Category, Service
from matching.matching_engine import CATEGORY_TAXONOMY

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
            "Tabmatch connects customers with trusted local service providers including "
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
                self.assertIn("How Tabmatch works", html)
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

    def test_logo_is_used_in_header_and_footer_and_all_icon_files_exist(self):
        from django.contrib.staticfiles import finders

        html = self.client.get("/").content.decode()
        self.assertEqual(html.count("website/images/logo-mark.svg"), 2)  # header + footer
        self.assertNotIn(">TA<", html)
        for name in ("logo-mark.svg", "favicon.svg", "favicon-32.png", "favicon-48.png",
                     "apple-touch-icon.png", "og-image.png"):
            self.assertIsNotNone(finders.find(f"website/images/{name}"), name)
        self.assertIn('rel="apple-touch-icon" sizes="180x180"', html)
        self.assertIn('rel="icon" type="image/svg+xml"', html)

    def test_social_share_image_tags_and_real_dimensions(self):
        import struct
        from django.contrib.staticfiles import finders

        html = self.client.get("/").content.decode()
        self.assertIn('property="og:image" content="http://testserver/static/website/images/og-image.png"', html)
        self.assertIn('name="twitter:card" content="summary_large_image"', html)

        def png_size(name):
            with open(finders.find(f"website/images/{name}"), "rb") as f:
                head = f.read(24)
            return struct.unpack(">II", head[16:24])

        self.assertEqual(png_size("og-image.png"), (1200, 630))
        self.assertEqual(png_size("apple-touch-icon.png"), (180, 180))

    def test_header_hides_wordmark_text_on_small_screens(self):
        css = open(__import__("django.contrib.staticfiles.finders", fromlist=["find"]).find("website/css/site.css"), encoding="utf-8").read()
        self.assertIn("max-width: 559px", css)
        self.assertIn(".site-header .brand-text { display: none; }", css)

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
        self.assertEqual(Sector.objects.count(), 8)
        self.assertEqual(SectorItem.objects.count(), 47)

    def test_every_item_resolves_to_an_active_backend_service(self):
        for item in SectorItem.objects.select_related("service"):
            self.assertTrue(item.service.is_active, item.label)

    def test_landscaping_is_one_service_in_two_sectors(self):
        self.assertEqual(Service.objects.filter(slug="landscaping").count(), 1)
        sectors = set(
            SectorItem.objects.filter(service__slug="landscaping").values_list("sector__slug", flat=True)
        )
        self.assertEqual(sectors, {"home-services", "outdoor-services"})

    def test_keyword_table_and_catalog_cover_exactly_the_same_services(self):
        slugs = set(Service.objects.values_list("slug", flat=True))
        self.assertEqual(slugs - set(CATEGORY_TAXONOMY), set(), "service with no keywords")
        self.assertEqual(set(CATEGORY_TAXONOMY) - slugs, set(), "keywords for a service not in the catalog")


@override_settings(API_KEY="test-key")
class ExistingRoutesStillWorkTests(TestCase):
    def test_admin_still_routes(self):
        self.assertEqual(self.client.get("/admin/").status_code, 302)

    def test_api_still_requires_key_and_serves_catalog(self):
        self.assertIn(self.client.get("/api/catalog/categories/").status_code, (401, 403))
        response = self.client.get("/api/catalog/categories/", HTTP_X_API_KEY="test-key")
        self.assertEqual(response.status_code, 200)
        # The app's catalog lists launched services only: the 9 launch
        # services all sit in one group.
        groups = response.json()
        self.assertEqual([g["slug"] for g in groups], ["trades-professional"])
        self.assertEqual(len(groups[0]["services"]), 9)


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
            html = self.client.get(f"/services/{service.slug}/", follow=True).content.decode()
            self.assertIn('class="title-row"', html, service.slug)
            self.assertRegex(html, r'icon-tile-hero">\s*<svg', service.slug)

    def test_home_has_hero_art_and_a_card_per_sector(self):
        html = self.client.get("/").content.decode()
        self.assertIn('class="hero-art"', html)
        self.assertEqual(html.count('class="sector-card"'), Sector.objects.count())

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
        from .linkcheck import orphan_services

        self.assertEqual(orphan_services(result["pages"]), [], "service pages nothing links to")
        self.assertEqual(expected - reached, set(), "pages that should be reachable from the site were not")
        self.assertEqual(result["broken"], [], result["broken"])


class OrphanFixTests(TestCase):
    def test_previously_orphaned_services_sit_in_the_intended_sectors(self):
        expected = {
            "metalwork-aluminum": "construction-renovation",
            "glass-mirrors": "construction-renovation",
            "tire-repair": "automotive-services",
            "event-decoration": "events-personal",
            "sound-lighting": "events-personal",
            "barber-services": "personal-services",
            "beauty-services": "personal-services",
            "personal-training": "personal-services",
            "tutoring": "personal-services",
            "carpentry": "construction-renovation",
            "home-repair": "home-services",
        }
        for service_slug, sector_slug in expected.items():
            self.assertTrue(
                SectorItem.objects.filter(service__slug=service_slug, sector__slug=sector_slug).exists(),
                service_slug,
            )

    def test_every_backend_service_is_on_the_website_sector_menu_or_has_an_seo_page(self):
        from .content.seo_pages import SEO_PAGE_BY_SERVICE

        listed = set(SectorItem.objects.values_list("service__slug", flat=True))
        for slug in Service.objects.values_list("slug", flat=True):
            self.assertTrue(slug in listed or slug in SEO_PAGE_BY_SERVICE, slug)

    def test_service_with_seo_page_redirects_instead_of_duplicating(self):
        response = self.client.get("/services/electrical/")
        self.assertEqual(response.status_code, 301)
        self.assertEqual(response["Location"], "/electrician-edmonton/")


class TabmatchBrandTests(TestCase):
    """The site is Tabmatch everywhere a visitor, a search engine or an admin can see a name."""

    PAGES = [
        "/", "/sectors/", "/providers/", "/how-it-works/", "/get-the-app/", "/contact/", "/privacy/", "/terms/",
        "/services/landscaping/", "/this-page-does-not-exist/",
    ]

    def test_no_page_still_carries_the_old_name_and_every_title_says_tabmatch(self):
        import re

        for path in self.PAGES:
            with self.subTest(path=path):
                html = self.client.get(path).content.decode()
                self.assertNotRegex(html, r"(?i)top[ -]?link|toplink", path)
                title = re.search(r"<title>(.*?)</title>", html, re.S).group(1)
                self.assertIn("Tabmatch", title)
                self.assertIn('property="og:site_name" content="Tabmatch"', html)

    def test_the_header_and_footer_show_the_two_colour_wordmark_and_the_new_mark(self):
        html = self.client.get("/").content.decode()
        wordmark = '<strong class="wordmark"><span class="wm-tab">tab</span><span class="wm-match">match</span></strong>'
        self.assertEqual(html.count(wordmark), 2)  # header + footer
        self.assertIn('aria-label="Tabmatch home"', html)
        self.assertIn("website/images/logo-mark.svg", html)

    def test_the_wordmark_colours_are_turquoise_match_and_white_or_navy_tab(self):
        from django.contrib.staticfiles import finders

        css = open(finders.find("website/css/site.css"), encoding="utf-8").read()
        self.assertIn(".wordmark .wm-match { color: #19C3B1; }", css)
        self.assertIn(".wordmark .wm-tab { color: #fff; }", css)
        self.assertIn(".on-light .wordmark .wm-tab { color: #0B1F3A; }", css)

    def test_the_logo_and_favicon_are_the_supplied_icon(self):
        from django.contrib.staticfiles import finders

        for name in ("logo-mark.svg", "favicon.svg"):
            svg = open(finders.find(f"website/images/{name}"), encoding="utf-8").read()
            self.assertIn('rx="230" fill="#0B1F3A"', svg, name)
            self.assertIn('stroke="#19C3B1"', svg, name)
            self.assertIn('aria-label="Tabmatch"', svg, name)
            self.assertNotIn("Top-Link", svg, name)

    def test_the_site_name_and_description_use_the_new_name(self):
        from . import config

        self.assertEqual(config.SITE_NAME, "Tabmatch")
        html = self.client.get("/").content.decode()
        self.assertIn('name="description" content="Tabmatch connects customers', html)

    def test_the_django_admin_is_branded(self):
        from django.contrib import admin
        from django.contrib.auth import get_user_model

        self.assertEqual(admin.site.site_header, "Tabmatch administration")
        self.assertEqual(admin.site.site_title, "Tabmatch admin")
        user = get_user_model().objects.create_superuser("boss", "boss@example.com", "pw-for-tests-123")
        self.client.force_login(user)
        page = self.client.get("/admin/").content.decode()
        self.assertIn("Tabmatch administration", page)
        self.assertIn("<title>Site administration | Tabmatch admin</title>", page)
        self.assertNotRegex(page, r"(?i)top[ -]?link")
