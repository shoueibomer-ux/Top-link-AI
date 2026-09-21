"""Crawl the website from the home page and verify every internal link.

Checks, for every page reachable from "/":
  - each internal <a href> and <link href> returns 200,
  - each /static/ file (css, js, images, favicons) exists,
  - each #fragment points at an id that exists on the target page.
External links (http/https/mailto/tel) are counted but not fetched.
"""

from html.parser import HTMLParser
from urllib.parse import urldefrag, urlparse

from django.contrib.staticfiles import finders

SKIP_SCHEMES = ("mailto:", "tel:", "http://", "https://", "javascript:", "data:")


class _Collector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []  # (tag, url)
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if a.get("id"):
            self.ids.add(a["id"])
        if tag in ("a", "link") and "href" in a:
            self.links.append((tag, a["href"]))
        elif tag in ("script", "img", "source") and "src" in a:
            self.links.append((tag, a["src"]))


def crawl(client, start="/"):
    pages, ids_by_path, edges = {}, {}, []
    queue, seen = [start], set()
    external = 0
    broken = []

    while queue:
        path = queue.pop()
        if path in seen:
            continue
        seen.add(path)
        response = client.get(path)
        if response.status_code != 200:
            broken.append((path, "(start/queued)", f"HTTP {response.status_code}"))
            continue
        if "text/html" not in response["Content-Type"]:
            continue
        collector = _Collector()
        collector.feed(response.content.decode())
        pages[path] = collector
        ids_by_path[path] = collector.ids
        for tag, url in collector.links:
            edges.append((path, tag, url))
            if url.startswith(SKIP_SCHEMES):
                continue
            target, _ = urldefrag(url)
            if not target:
                continue
            if target.startswith("/") and not target.startswith("/static/"):
                queue.append(target.split("?")[0])

    checked = 0
    for source, tag, url in edges:
        if url.startswith(SKIP_SCHEMES):
            external += 1
            continue
        checked += 1
        target, fragment = urldefrag(url)
        parsed = urlparse(target)
        path = parsed.path or source
        if path.startswith("/static/"):
            if not finders.find(path[len("/static/"):]):
                broken.append((source, url, "static file missing"))
            continue
        if not path.startswith("/"):
            broken.append((source, url, "relative link (unexpected)"))
            continue
        if path not in pages:
            broken.append((source, url, "target page not reachable / not 200"))
            continue
        if fragment and fragment not in ids_by_path[path]:
            broken.append((source, url, f"no element with id '{fragment}'"))
    return {
        "pages": sorted(pages),
        "links_checked": checked,
        "external_skipped": external,
        "broken": sorted(set(broken)),
    }
