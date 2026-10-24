import json
from xml.sax.saxutils import escape

from django.http import Http404, HttpResponse, JsonResponse
from django.shortcuts import redirect, render
from django.views.decorators.http import require_GET

from catalog.taxonomy import launched_slugs
from config.site_url import absolute_url

from . import config, local_pages, selectors
from .content.icons import SEO_PAGE_ICONS
from .content.pages import (
    HERO_CLUSTER_HOME,
    HERO_CLUSTER_PROVIDERS,
    HOW_IT_WORKS,
    JOURNEY_STEPS,
    PROVIDER_FEATURES,
    TRUST_POINTS,
)
from .content.neighbourhoods import NEIGHBOURHOODS
from .content.seo_pages import SEO_PAGE_BY_SERVICE, SEO_PAGES

_COMMON = {
    "journey_steps": JOURNEY_STEPS,
    "how_it_works": HOW_IT_WORKS,
    "trust_points": TRUST_POINTS,
}


def _jsonld(data: dict) -> str:
    # "</" is escaped so the payload can never close its own <script> tag.
    return json.dumps(data).replace("</", "<\\/")


def _meta(title: str, description: str, robots: str = "index,follow") -> dict:
    return {"meta": {"title": title, "description": description, "robots": robots}}


def home(request):
    seo_links = [(slug, page["breadcrumb"]) for slug, page in SEO_PAGES.items()]
    meta = _meta(
        "Tabmatch | Trusted Local Service Providers",
        "Tabmatch connects customers with trusted local service providers including electricians, plumbers, cleaners, contractors, and other professionals.",
    )
    return render(request, "website/home.html", {**_COMMON, **meta, "seo_links": seo_links, "hero_icons": HERO_CLUSTER_HOME})


def sectors(request):
    meta = _meta(
        "All Services and Sectors | Tabmatch",
        "Browse every Tabmatch service: home services, construction and renovation, automotive, business, outdoor, moving and delivery, events and personal services.",
    )
    return render(request, "website/sectors.html", {**_COMMON, **meta})


def providers(request):
    meta = _meta(
        "Join Tabmatch as a Service Provider",
        "Register your business on Tabmatch, list your services and categories, and reach local customers. Manage your provider profile from the app.",
    )
    return render(request, "website/providers.html", {**_COMMON, **meta, "provider_features": PROVIDER_FEATURES, "hero_icons": HERO_CLUSTER_PROVIDERS})


def how_it_works(request):
    meta = _meta(
        "How Tabmatch Works | From Search to Service",
        "See how Tabmatch takes you from a Google search to a local provider: choose a service, compare providers, request the job and connect through the app.",
    )
    return render(request, "website/how_it_works.html", {**_COMMON, **meta})


def get_app(request):
    meta = _meta("Get the Tabmatch App", "Get the Tabmatch app to request services and manage your provider profile.", "noindex,follow")
    return render(request, "website/get_app.html", {**meta, "as_provider": request.GET.get("as") == "provider"})


def seo_page(request, slug):
    page = SEO_PAGES.get(slug)
    if page is None:
        raise Http404
    related_slugs = page.get("related_service_slugs", [])
    related = [s for s in (selectors.get_service(x) for x in related_slugs) if s]
    url = absolute_url(request, request.path)
    jsonld = [
        {
            "@context": "https://schema.org",
            "@type": "Service",
            "name": f"{page['keyword'].title()} in {config.CITY}",
            "serviceType": page["keyword"],
            "areaServed": {"@type": "City", "name": config.CITY},
            "provider": {"@type": "Organization", "name": config.SITE_NAME},
            "description": page["description"],
            "url": url,
        },
        {
            "@context": "https://schema.org",
            "@type": "FAQPage",
            "mainEntity": [
                {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}}
                for q, a in page["faqs"]
            ],
        },
        {
            "@context": "https://schema.org",
            "@type": "BreadcrumbList",
            "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": "Home", "item": absolute_url(request, "/")},
                {"@type": "ListItem", "position": 2, "name": page["breadcrumb"], "item": url},
            ],
        },
    ]
    return render(
        request,
        "website/service_page.html",
        {
            **_COMMON,
            **_meta(page["title"], page["description"]),
            "page": page,
            "page_icon": SEO_PAGE_ICONS.get(slug),
            "related": related,
            # Only a launched service can be requested; the others keep the plain get-the-app link.
            "request_url": (
                local_pages.request_url(page["service_slug"], slug)
                if page["service_slug"] in launched_slugs()
                else ""
            ),
            "local_links": (
                [(local_pages.page_path(n["slug"], page["service_slug"]), n["name"]) for n in NEIGHBOURHOODS]
                if page["service_slug"] in local_pages.live_service_slugs()
                else []
            ),
            "jsonld": [_jsonld(x) for x in jsonld],
        },
    )


def local_page(request, neighbourhood, service):
    """/edmonton/<neighbourhood>/<service>/ — see website.local_pages."""
    page = local_pages.build_page(neighbourhood, service)
    if page is None:
        raise Http404
    n = page["neighbourhood"]
    url = absolute_url(request, request.path)
    jsonld = [
        {
            "@context": "https://schema.org",
            "@type": "Service",
            "name": page["h1"],
            "serviceType": page["service"]["label"],
            "description": page["description"],
            "url": url,
            "areaServed": {
                "@type": "Place",
                "name": f"{n['name']}, {config.CITY}",
                "containedInPlace": {"@type": "City", "name": config.CITY, "address": {
                    "@type": "PostalAddress", "addressLocality": config.CITY, "addressRegion": "AB", "addressCountry": "CA",
                }},
            },
            "provider": {"@type": "Organization", "name": config.SITE_NAME, "url": absolute_url(request, "/")},
        },
        {
            "@context": "https://schema.org",
            "@type": "FAQPage",
            "mainEntity": [
                {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}}
                for q, a in page["faqs"]
            ],
        },
        {
            "@context": "https://schema.org",
            "@type": "BreadcrumbList",
            "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": "Home", "item": absolute_url(request, "/")},
                {"@type": "ListItem", "position": 2, "name": config.CITY, "item": absolute_url(request, "/edmonton/")},
                {"@type": "ListItem", "position": 3, "name": n["name"],
                 "item": absolute_url(request, local_pages.hub_path(n["slug"]))},
                {"@type": "ListItem", "position": 4, "name": page["service"]["label"], "item": url},
            ],
        },
    ]
    return render(
        request,
        "website/local_page.html",
        {**_COMMON, **_meta(page["title"], page["description"]), "page": page, "jsonld": [_jsonld(x) for x in jsonld]},
    )


def neighbourhood_hub(request, neighbourhood):
    hub = local_pages.build_hub(neighbourhood)
    if hub is None:
        raise Http404
    return render(request, "website/neighbourhood_hub.html", {**_meta(hub["title"], hub["description"]), "hub": hub})


def edmonton_index(request):
    meta = _meta(
        "Edmonton Neighbourhoods | Tabmatch",
        "Find local plumbers, electricians, furnace technicians, painters and more in your Edmonton neighbourhood with Tabmatch.",
    )
    return render(request, "website/edmonton_index.html", {**meta, "groups": local_pages.build_index()})


def service_detail(request, slug):
    # A service with a dedicated SEO page lives there; the generic page would
    # be a near-duplicate, so send visitors (and crawlers) to the real one.
    if slug in SEO_PAGE_BY_SERVICE:
        return redirect(f"/{SEO_PAGE_BY_SERVICE[slug]}/", permanent=True)
    service = selectors.get_service(slug)
    if service is None:
        raise Http404
    # noindex until each service has unique copy; the 5 dedicated pages are
    # the SEO targets, and thin generated pages shouldn't dilute them.
    meta = _meta(
        f"{service.name} in {config.CITY} | Tabmatch",
        (service.what_we_cover or f"Find {service.name} providers in {config.CITY} with Tabmatch.")[:155],
        "noindex,follow",
    )
    return render(request, "website/service_detail.html", {**_COMMON, **meta, "service": service})


def contact(request):
    meta = _meta("Contact Tabmatch", "Get in touch with Tabmatch about the app, your provider profile, or working with us.")
    return render(request, "website/contact.html", meta)


def privacy(request):
    meta = _meta("Privacy Policy (Draft) | Tabmatch", "Draft privacy policy describing what Tabmatch collects and why.", "noindex,follow")
    return render(request, "website/privacy.html", meta)


def terms(request):
    meta = _meta("Terms of Service (Draft) | Tabmatch", "Draft terms of service for Tabmatch.", "noindex,follow")
    return render(request, "website/terms.html", meta)


def provider_agreement(request):
    meta = _meta(
        "Provider Agreement (Draft) | Tabmatch", "Draft agreement for service providers who use Tabmatch.", "noindex,follow"
    )
    return render(request, "website/provider_agreement.html", meta)


def delete_account(request):
    """Where Google Play's "account deletion" URL points: how to delete an account, what goes and what is kept."""
    meta = _meta(
        "Delete your account | Tabmatch",
        "How to delete your Tabmatch account and your data, what is removed and what is kept.",
    )
    return render(request, "website/delete_account.html", meta)


def not_found(request, exception=None):
    """Site-wide 404 (wired up as handler404 in config/urls.py). Unmatched /api/
    paths get JSON so API clients never receive the website's HTML page."""
    if request.path.startswith("/api/"):
        return JsonResponse({"detail": "Not found."}, status=404)
    meta = _meta("Page not found | Tabmatch", "The page you were looking for could not be found.", "noindex,follow")
    return render(request, "404.html", meta, status=404)


@require_GET
def robots_txt(request):
    lines = [
        "User-agent: *",
        "Allow: /",
        "Disallow: /admin/",
        "Disallow: /api/",
        # Links into the app (request, invite) and email-only pages: nothing to index there.
        "Disallow: /open/",
        "Disallow: /invite/",
        "Disallow: /reminders/",
        "Allow: /edmonton/",
        f"Sitemap: {absolute_url(request, '/sitemap.xml')}",
        "",
    ]
    return HttpResponse("\n".join(lines), content_type="text/plain")


@require_GET
def sitemap_xml(request):
    paths = ["/", "/sectors/", "/providers/", "/how-it-works/", "/contact/", "/delete-account/"] + [
        f"/{slug}/" for slug in SEO_PAGES
    ] + local_pages.all_paths()
    urls = "".join(
        f"<url><loc>{escape(absolute_url(request, p))}</loc></url>" for p in paths
    )
    xml = f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>'
    return HttpResponse(xml, content_type="application/xml")
