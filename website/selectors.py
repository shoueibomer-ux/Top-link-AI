"""Read-only access to the sector/service tree for website views and
templates. The single place the website touches catalog data."""

from catalog.models import Service

from .content.seo_pages import SEO_PAGE_BY_SERVICE
from .models import Sector


def service_url(service_slug: str) -> str:
    """URL a dropdown item should link to: the dedicated SEO page if the
    service has one, otherwise its generated detail page."""
    seo_slug = SEO_PAGE_BY_SERVICE.get(service_slug)
    if seo_slug:
        return f"/{seo_slug}/"
    return f"/services/{service_slug}/"


def get_sector_tree() -> list[dict]:
    """Active sectors, each with its active items whose backend service is
    also active, in display order."""
    sectors = Sector.objects.filter(is_active=True).prefetch_related(
        "items__service__category"
    )
    tree = []
    for sector in sectors:
        items = [
            {
                "label": item.label,
                "service_slug": item.service.slug,
                "category": item.service.category.name,
                "url": service_url(item.service.slug),
            }
            for item in sector.items.all()
            if item.is_active and item.service.is_active
        ]
        tree.append({"name": sector.name, "slug": sector.slug, "blurb": sector.blurb, "items": items})
    return tree


def get_service(slug: str) -> Service | None:
    return (
        Service.objects.filter(slug=slug, is_active=True)
        .select_related("category")
        .first()
    )
