"""Inline SVG icons (vendored Lucide, ISC licence — see static/website/icons/LICENSE.txt).

Icons are inlined rather than <img> so CSS can colour them via currentColor,
and read from disk once (lru_cache). Anything unknown falls back to a generic
icon, so a service added later in admin never breaks a page.
"""

import re
from functools import lru_cache
from pathlib import Path

from django.utils.html import escape
from django.utils.safestring import mark_safe

ICON_DIR = Path(__file__).resolve().parent / "static" / "website" / "icons"
FALLBACK = "wrench"

_COMMENT = re.compile(r"<!--.*?-->", re.S)
_SIZE_ATTRS = re.compile(r'\s(?:width|height)="\d+"')
_CLASS = re.compile(r'class="[^"]*"')


@lru_cache(maxsize=None)
def _load(name: str) -> str | None:
    path = ICON_DIR / f"{name}.svg"
    if not path.is_file():
        return None
    return _COMMENT.sub("", path.read_text(encoding="utf-8")).strip()


def render_icon(name: str, css_class: str = "") -> str:
    svg = _load(name) or _load(FALLBACK)
    classes = f"icon {css_class}".strip()
    svg = _CLASS.sub(f'class="{escape(classes)}" aria-hidden="true" focusable="false"', svg, count=1)
    # width/height are dropped so CSS controls size; the viewBox keeps the ratio.
    head, _, rest = svg.partition(">")
    return mark_safe(_SIZE_ATTRS.sub("", head) + ">" + rest)
