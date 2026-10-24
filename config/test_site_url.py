from django.conf import settings
from django.test import SimpleTestCase, TestCase, override_settings

from config.hosts import csrf_trusted_origins, site_redirect_hosts

SITE = "https://tabmatch.ca"
APEX = "tabmatch.ca"
WWW = "www.tabmatch.ca"
RENDER = "toplinkai-backend.onrender.com"

# What production looks like: DJANGO_ALLOWED_HOSTS=tabmatch.ca,www.tabmatch.ca plus RENDER_EXTERNAL_HOSTNAME.
PRODUCTION = override_settings(
    SITE_URL=SITE,
    ALLOWED_HOSTS=[APEX, WWW, RENDER],
    SITE_REDIRECT_HOSTS=site_redirect_hosts(SITE, RENDER),
)


class HostListTests(SimpleTestCase):
    def test_every_allowed_host_is_a_trusted_csrf_origin(self):
        self.assertEqual(
            csrf_trusted_origins([APEX, WWW, RENDER]),
            ["https://tabmatch.ca", "https://www.tabmatch.ca", "https://toplinkai-backend.onrender.com"],
        )
        self.assertEqual(csrf_trusted_origins([".tabmatch.ca", "*"]), ["https://*.tabmatch.ca"])

    def test_www_and_the_onrender_host_redirect_but_the_site_itself_does_not(self):
        self.assertEqual(site_redirect_hosts(SITE, RENDER), {WWW, RENDER})
        self.assertEqual(site_redirect_hosts(SITE, None), {WWW})
        self.assertEqual(site_redirect_hosts(SITE, APEX), {WWW})

    def test_nothing_redirects_without_an_https_site_url(self):
        self.assertEqual(site_redirect_hosts("http://localhost:8000", RENDER), set())
        self.assertEqual(site_redirect_hosts("", RENDER), set())


@PRODUCTION
class CanonicalHostRedirectTests(TestCase):
    def get(self, path, host, **extra):
        return self.client.get(path, HTTP_HOST=host, secure=True, **extra)

    def assertRedirectsToSite(self, response, path):
        self.assertEqual(response.status_code, 301)
        self.assertEqual(response["Location"], SITE + path)

    def test_website_pages_on_www_and_onrender_redirect_to_the_site(self):
        for host in (WWW, RENDER):
            with self.subTest(host=host):
                self.assertRedirectsToSite(self.get("/", host), "/")
                self.assertRedirectsToSite(self.get("/plumber-edmonton/", host), "/plumber-edmonton/")
                self.assertRedirectsToSite(self.get("/sitemap.xml", host), "/sitemap.xml")
                self.assertRedirectsToSite(self.get("/open/request/?service=hvac&src=seasonal", host),
                                           "/open/request/?service=hvac&src=seasonal")
                self.assertRedirectsToSite(self.client.head("/", HTTP_HOST=host, secure=True), "/")

    def test_the_site_itself_is_served(self):
        self.assertEqual(self.get("/", APEX).status_code, 200)
        self.assertEqual(self.get("/plumber-edmonton/", APEX).status_code, 200)

    def test_the_api_is_never_redirected_so_installed_app_builds_keep_working(self):
        for host in (WWW, RENDER):
            with self.subTest(host=host):
                response = self.get("/api/catalog/does-not-exist/", host)
                self.assertEqual(response.status_code, 404)
                self.assertEqual(response.json(), {"detail": "Not found."})
                post = self.client.post("/api/growth/invite/claim/", {}, HTTP_HOST=host, secure=True)
                self.assertNotEqual(post.status_code, 301)

    def test_robots_txt_answers_200_on_the_onrender_host_for_the_health_check(self):
        response = self.get("/robots.txt", RENDER)
        self.assertEqual(response.status_code, 200)
        self.assertIn(f"Sitemap: {SITE}/sitemap.xml", response.content.decode())

    def test_posts_are_never_redirected(self):
        # Mail apps' one-click unsubscribe POSTs straight to the link in the email.
        response = self.client.post("/reminders/unsubscribe/not-a-token/", HTTP_HOST=RENDER, secure=True)
        self.assertNotEqual(response.status_code, 301)

    def test_the_admin_is_not_redirected(self):
        admin = "/" + settings.ADMIN_URL_PATH
        self.assertNotEqual(self.get(admin + "login/", RENDER).status_code, 301)
        no_slash = self.get(admin.rstrip("/"), RENDER)
        self.assertNotEqual(no_slash.get("Location", ""), SITE + admin.rstrip("/"))


@override_settings(SITE_URL=SITE, ALLOWED_HOSTS=[APEX, RENDER], SITE_REDIRECT_HOSTS=set())
class AbsoluteLinksUseSiteUrlTests(TestCase):
    """Whatever host a page is fetched on, its absolute links name SITE_URL."""

    def get(self, path):
        return self.client.get(path, HTTP_HOST=RENDER, secure=True).content.decode()

    def test_canonical_and_social_tags(self):
        html = self.get("/plumber-edmonton/")
        self.assertIn(f'<link rel="canonical" href="{SITE}/plumber-edmonton/">', html)
        self.assertIn(f'<meta property="og:url" content="{SITE}/plumber-edmonton/">', html)
        self.assertIn(f'property="og:image" content="{SITE}/static/website/images/og-image.png"', html)
        self.assertIn(f'"url": "{SITE}/plumber-edmonton/"', html)  # JSON-LD
        self.assertNotIn(RENDER, html)

    def test_canonical_drops_the_query_string(self):
        self.assertIn(f'<link rel="canonical" href="{SITE}/">', self.get("/?utm_source=x"))

    def test_sitemap_and_robots(self):
        sitemap = self.get("/sitemap.xml")
        self.assertIn(f"<loc>{SITE}/</loc>", sitemap)
        self.assertIn(f"<loc>{SITE}/plumber-edmonton/</loc>", sitemap)
        self.assertNotIn(RENDER, sitemap)
        self.assertIn(f"Sitemap: {SITE}/sitemap.xml", self.get("/robots.txt"))

    @override_settings(SITE_URL="")
    def test_without_site_url_links_fall_back_to_the_requested_host(self):
        self.assertIn(f"<loc>https://{RENDER}/</loc>", self.get("/sitemap.xml"))
