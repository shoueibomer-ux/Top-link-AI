import json
from xml.sax.saxutils import escape

from django.http import Http404, HttpResponse
from django.shortcuts import render
from django.views.decorators.http import require_GET

from . import config, selectors
from .content.pages import HOW_IT_WORKS, JOURNEY_STEPS, PROVIDER_FEATURES, TRUST_POINTS
from .content.seo_pages import SEO_PAGES

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
        "Top-Link | Trusted Local Service Providers",
        "Top-Link connects customers with trusted local service providers including electricians, plumbers, cleaners, contractors, and other professionals.",
    )
    return render(request, "website/home.html", {**_COMMON, **meta, "seo_links": seo_links})


def sectors(request):
    meta = _meta(
        "All Services and Sectors | Top-Link",
        "Browse every Top-Link service: home services, construction and renovation, automotive, business, outdoor, moving and delivery, events and personal services.",
    )
    return render(request, "website/sectors.html", {**_COMMON, **meta})


def providers(request):
    meta = _meta(
        "Join Top-Link as a Service Provider",
        "Register your business on Top-Link, list your services and categories, and reach local customers. Manage your provider profile from the app.",
    )
    return render(request, "website/providers.html", {**_COMMON, **meta, "provider_features": PROVIDER_FEATURES})


def how_it_works(request):
    meta = _meta(
        "How Top-Link Works | From Search to Service",
        "See how Top-Link takes you from a Google search to a local provider: choose a service, compare providers, request the job and connect through the app.",
    )
    return render(request, "website/how_it_works.html", {**_COMMON, **meta})


def get_app(request):
    meta = _meta("Get the Top-Link App", "Get the Top-Link app to request services and manage your provider profile.", "noindex,follow")
    return render(request, "website/get_app.html", {**meta, "as_provider": request.GET.get("as") == "provider"})


def seo_page(request, slug):
    page = SEO_PAGES.get(slug)
    if page is None:
        raise Http404
    related_slugs = page.get("related_service_slugs", [])
    related = [s for s in (selectors.get_service(x) for x in related_slugs) if s]
    url = request.build_absolute_uri()
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
                {"@type": "ListItem", "position": 1, "name": "Home", "item": request.build_absolute_uri("/")},
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
            "related": related,
            "jsonld": [_jsonld(x) for x in jsonld],
        },
    )


def service_detail(request, slug):
    service = selectors.get_service(slug)
    if service is None:
        raise Http404
    # noindex until each service has unique copy; the 5 dedicated pages are
    # the SEO targets, and thin generated pages shouldn't dilute them.
    meta = _meta(
        f"{service.name} in {config.CITY} | Top-Link",
        (service.what_we_cover or f"Find {service.name} providers in {config.CITY} with Top-Link.")[:155],
        "noindex,follow",
    )
    return render(request, "website/service_detail.html", {**_COMMON, **meta, "service": service})


@require_GET
def robots_txt(request):
    lines = [
        "User-agent: *",
        "Allow: /",
        "Disallow: /admin/",
        "Disallow: /api/",
        f"Sitemap: {request.build_absolute_uri('/sitemap.xml')}",
        "",
    ]
    return HttpResponse("\n".join(lines), content_type="text/plain")


@require_GET
def sitemap_xml(request):
    paths = ["/", "/sectors/", "/providers/", "/how-it-works/"] + [f"/{slug}/" for slug in SEO_PAGES]
    urls = "".join(
        f"<url><loc>{escape(request.build_absolute_uri(p))}</loc></url>" for p in paths
    )
    xml = f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>'
    return HttpResponse(xml, content_type="application/xml")
