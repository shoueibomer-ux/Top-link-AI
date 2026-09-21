from django import template
from django.urls import reverse

from .. import config, selectors
from ..content.icons import SECTOR_ICONS, SERVICE_ICONS
from ..icons import FALLBACK, render_icon

register = template.Library()


@register.simple_tag
def sector_tree():
    return selectors.get_sector_tree()


@register.simple_tag
def site():
    """Site constants plus the resolved CTA destinations."""
    get_app = reverse("website:get-app")
    return {
        "name": config.SITE_NAME,
        "tagline": config.TAGLINE,
        "city": config.CITY,
        "region": config.REGION,
        "contact_email": config.CONTACT_EMAIL,
        "app_url": config.APP_URL or get_app,
        "provider_url": config.PROVIDER_URL or reverse("website:get-app") + "?as=provider",
    }


@register.simple_tag
def icon(name, css_class=""):
    """{% icon "zap" "tile-icon" %} — an inline Lucide SVG."""
    return render_icon(name, css_class)


@register.simple_tag
def service_icon(slug, css_class=""):
    return render_icon(SERVICE_ICONS.get(slug, FALLBACK), css_class)


@register.simple_tag
def sector_icon(slug, css_class=""):
    return render_icon(SECTOR_ICONS.get(slug, "layout-grid"), css_class)
