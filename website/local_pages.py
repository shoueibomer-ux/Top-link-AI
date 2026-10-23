"""Neighbourhood landing pages: one per launched service and Edmonton
neighbourhood, at /edmonton/<neighbourhood>/<service>/, plus a hub page per
neighbourhood and an index at /edmonton/.

Everything is generated from website.content.neighbourhoods and
website.content.local_services. A page only exists while its service is
launched (catalog.Service.is_launched) and has copy in LOCAL_SERVICES, so
un-launching a service takes its pages, and their sitemap entries, down.
"""

from catalog.taxonomy import launched_slugs
from growth import links

from . import config
from .content.local_services import LOCAL_SERVICES
from .content.neighbourhoods import ERAS, GROUPS, NEIGHBOURHOOD_BY_SLUG, NEIGHBOURHOODS, nearby

TITLE_MAX = 60
DESCRIPTION_MAX = 160


def live_service_slugs() -> list[str]:
    """Services that get neighbourhood pages right now, in LOCAL_SERVICES order."""
    launched = launched_slugs()
    return [slug for slug in LOCAL_SERVICES if slug in launched]


def page_path(neighbourhood_slug: str, service_slug: str) -> str:
    return f"/edmonton/{neighbourhood_slug}/{service_slug}/"


def hub_path(neighbourhood_slug: str) -> str:
    return f"/edmonton/{neighbourhood_slug}/"


def all_paths() -> list[str]:
    """Every neighbourhood page that exists right now, for the sitemap."""
    services = live_service_slugs()
    paths = ["/edmonton/"]
    for n in NEIGHBOURHOODS:
        paths.append(hub_path(n["slug"]))
        paths += [page_path(n["slug"], s) for s in services]
    return paths


def request_url(service_slug: str, ref: str) -> str:
    """The "Request this service" link: opens the app's request flow with the
    service chosen, and tells the server the request came from an SEO page."""
    return links.open_request_path(service_slug, "seo", ref)


def _join(names: list[str]) -> str:
    if len(names) <= 1:
        return "".join(names)
    return f"{', '.join(names[:-1])} and {names[-1]}"


def _title(service: dict, neighbourhood: dict) -> str:
    title = f"{service['title']} in {neighbourhood['name']}, {config.CITY} | {config.SITE_NAME}"
    if len(title) > TITLE_MAX:
        title = f"{service['title']} in {neighbourhood['name']} | {config.SITE_NAME}"
    return title


def _description(service: dict, neighbourhood: dict) -> str:
    area = GROUPS[neighbourhood["group"]]
    first = f"Need a {service['noun']} in {neighbourhood['name']}, {area}? Tabmatch sends your request to approved local {service['nouns']}."
    jobs = f" {service['jobs'][0]}, {service['jobs'][1].lower()} and more."
    return first + jobs if len(first + jobs) <= DESCRIPTION_MAX else first


def build_page(neighbourhood_slug: str, service_slug: str) -> dict | None:
    """Everything the template shows for one page, or None if the page doesn't exist."""
    n = NEIGHBOURHOOD_BY_SLUG.get(neighbourhood_slug)
    service = LOCAL_SERVICES.get(service_slug)
    if n is None or service is None:
        return None
    live = live_service_slugs()
    if service_slug not in live:
        return None
    near = nearby(n)
    near_names = [x["name"] for x in near]
    label = service["label"].lower()
    area = GROUPS[n["group"]]

    housing = [n["homes"], service["era"][n["era"]]]
    housing += [service["flags"][f] for f in n["flags"] if f in service["flags"]]
    housing += [service[trait][n[trait]] for trait in ("garage", "basement") if n[trait]]
    faqs = [
        (
            f"Do Tabmatch {service['nouns']} work in {n['name']}?",
            f"Yes. Tabmatch covers all of {config.CITY}, including {n['name']}"
            + (f" and nearby {_join(near_names)}" if near_names else "")
            + f". Send your {label} request in the app; approved local {service['nouns']} can accept it, and you'll see who did and can chat with them there.",
        ),
        (
            f"What are homes like in {n['name']}?",
            f"{n['homes']} {n['name']} is in {area}, and most of it is {ERAS[n['era']]}.",
        ),
        (
            f"Anything to tell a {service['noun']} visiting {n['name']}?",
            f"{n['access']} You can add notes like this to the description when you send your request.",
        ),
        *service["faqs"],
    ]
    return {
        "neighbourhood": n,
        "service": service,
        "service_slug": service_slug,
        "area": area,
        "era": ERAS[n["era"]],
        "title": _title(service, n),
        "description": _description(service, n),
        "h1": f"{service['title']} in {n['name']}, {config.CITY}",
        "intro": [service["intro"], n["blurb"]],
        "housing": housing,
        "jobs": service["jobs"],
        "season": service["season"],
        "faqs": faqs,
        "request_url": request_url(service_slug, n["slug"]),
        "nearby_links": [(page_path(x["slug"], service_slug), x["name"]) for x in near],
        "other_services": [
            (page_path(n["slug"], s), LOCAL_SERVICES[s]["label"]) for s in live if s != service_slug
        ],
        "path": page_path(n["slug"], service_slug),
    }


def page_text(page: dict) -> str:
    """The page's own words (no shared site chrome), for checking that pages
    aren't near-duplicates of each other."""
    parts = [page["h1"], *page["intro"], *page["housing"], *page["jobs"], page["season"]]
    parts += [f"{q} {a}" for q, a in page["faqs"]]
    parts += [name for _, name in page["nearby_links"]]
    return " ".join(parts)


def build_hub(neighbourhood_slug: str) -> dict | None:
    n = NEIGHBOURHOOD_BY_SLUG.get(neighbourhood_slug)
    if n is None:
        return None
    return {
        "neighbourhood": n,
        "area": GROUPS[n["group"]],
        "title": f"Home Services in {n['name']}, {config.CITY} | {config.SITE_NAME}",
        "description": f"Plumbers, electricians, furnace technicians, painters and more in {n['name']}, {GROUPS[n['group']]}. Request local services through Tabmatch.",
        "services": [(page_path(n["slug"], s), LOCAL_SERVICES[s]["title"], s) for s in live_service_slugs()],
        "nearby_links": [(hub_path(x["slug"]), x["name"]) for x in nearby(n)],
    }


def build_index() -> list[dict]:
    """Neighbourhoods grouped by part of the city, for /edmonton/."""
    return [
        {
            "label": label,
            "links": [(hub_path(n["slug"]), n["name"]) for n in NEIGHBOURHOODS if n["group"] == group],
        }
        for group, label in GROUPS.items()
    ]
