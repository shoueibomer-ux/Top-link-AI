from django.urls import path

from . import views
from .content.seo_pages import SEO_PAGES

app_name = "website"

urlpatterns = [
    path("", views.home, name="home"),
    path("sectors/", views.sectors, name="sectors"),
    path("providers/", views.providers, name="providers"),
    path("how-it-works/", views.how_it_works, name="how-it-works"),
    path("get-the-app/", views.get_app, name="get-app"),
    path("contact/", views.contact, name="contact"),
    path("privacy/", views.privacy, name="privacy"),
    path("terms/", views.terms, name="terms"),
    path("services/<slug:slug>/", views.service_detail, name="service-detail"),
    path("robots.txt", views.robots_txt, name="robots"),
    path("sitemap.xml", views.sitemap_xml, name="sitemap"),
]

# One explicit route per SEO page (no catch-all, so nothing else is shadowed).
urlpatterns += [
    path(f"{slug}/", views.seo_page, {"slug": slug}, name=f"seo-{slug}") for slug in SEO_PAGES
]
