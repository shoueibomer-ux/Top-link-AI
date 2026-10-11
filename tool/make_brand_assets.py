"""Regenerates every Tabmatch brand raster from the icon's geometry.

    python tool/make_brand_assets.py

The source of truth is assets/brand/tabmatch_icon.svg (and the transparent
tabmatch_icon_foreground.svg: the same shapes without the navy tile). This
script draws that same geometry with Pillow, so no SVG renderer is needed, and
writes:

  assets/brand/        icon PNGs (1024, 512, 192, 180, 48, favicon 32), the iOS
                       (opaque, square) icon, the Android adaptive foreground
                       and monochrome layers, the splash image, and the
                       "tabmatch" wordmark on dark and light backgrounds
  website/static/website/images/   favicon, apple-touch icon, social image

Platform launcher icons and the native splash screens are produced from these
by `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`
(see pubspec.yaml).

Needs Pillow (`pip install pillow`): a build-time tool only, not an app or
backend dependency. The wordmark uses Roboto Bold from the Flutter SDK
(material_fonts), the same face the app's text uses.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "assets" / "brand"
SITE_IMAGES = ROOT / "website" / "static" / "website" / "images"

NAVY = "#0B1F3A"
TURQUOISE = "#19C3B1"
WHITE = "#FFFFFF"

# The icon's geometry, in its 1024x1024 viewBox (see tabmatch_icon.svg).
TILE_RADIUS = 230
STROKE = 70
T_BAR = ((192, 314), (704, 314))
T_STEM = ((378, 314), (378, 717))
M_POINTS = [(506, 442), (621, 570), (832, 294), (832, 717)]

SUPERSAMPLE = 4  # drawn 4x larger then shrunk, for smooth edges

FONT_CANDIDATES = [
    Path("C:/src/flutter/bin/cache/artifacts/material_fonts/roboto-bold.ttf"),
    Path("C:/Windows/Fonts/arialbd.ttf"),
]


def _thick_line(draw, p1, p2, width, fill):
    """A stroke with round caps, drawn as an exact rectangle plus two discs
    (Pillow's own line() has flat ends and rounds its width to whole pixels)."""
    (x1, y1), (x2, y2) = p1, p2
    length = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
    r = width / 2
    nx, ny = -(y2 - y1) / length * r, (x2 - x1) / length * r
    draw.polygon([(x1 + nx, y1 + ny), (x2 + nx, y2 + ny), (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)], fill=fill)
    for x, y in (p1, p2):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def _glyph(draw, k, ox, oy, t_color, m_color):
    """The T and the m, scaled by k and shifted by (ox, oy)."""

    def pt(p):
        return (ox + p[0] * k, oy + p[1] * k)

    w = STROKE * k
    _thick_line(draw, pt(T_BAR[0]), pt(T_BAR[1]), w, t_color)
    _thick_line(draw, pt(T_STEM[0]), pt(T_STEM[1]), w, t_color)
    for a, b in zip(M_POINTS, M_POINTS[1:]):
        _thick_line(draw, pt(a), pt(b), w, m_color)


def render_mark(size, *, tile=True, full_bleed=False, glyph_scale=1.0, mono=False):
    """The icon at size x size px. tile=False leaves out the navy tile;
    full_bleed makes the tile a square with no rounded corners (iOS icons must
    be opaque and square); glyph_scale shrinks the glyph about the centre;
    mono draws the whole glyph in white (Android's themed-icon layer)."""
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    if tile:
        radius = 0 if full_bleed else TILE_RADIUS * big / 1024
        draw.rounded_rectangle((0, 0, big - 1, big - 1), radius=radius, fill=NAVY)
    k = big / 1024 * glyph_scale
    offset = big * (1 - glyph_scale) / 2
    _glyph(draw, k, offset, offset, WHITE, WHITE if mono else TURQUOISE)
    return img.resize((size, size), Image.LANCZOS)


def _font(px):
    for path in FONT_CANDIDATES:
        if path.exists():
            return ImageFont.truetype(str(path), px)
    raise SystemExit("No bold font found; install the Flutter SDK or edit FONT_CANDIDATES.")


def render_wordmark(height, tab_color, on=None):
    """"tabmatch" in lowercase: "tab" in tab_color, "match" in turquoise."""
    font = _font(height * SUPERSAMPLE)
    big_h = height * SUPERSAMPLE
    tab_w = font.getlength("tab")
    match_w = font.getlength("match")
    pad = big_h // 4
    img = Image.new("RGBA", (round(tab_w + match_w) + pad * 2, round(big_h * 1.5)), on or (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    baseline = round(big_h * 1.15)
    draw.text((pad, baseline), "tab", font=font, fill=tab_color, anchor="ls")
    draw.text((pad + tab_w, baseline), "match", font=font, fill=TURQUOISE, anchor="ls")
    bbox = img.getbbox()
    img = img.crop((max(bbox[0] - pad // 2, 0), max(bbox[1] - pad // 2, 0), bbox[2] + pad // 2, bbox[3] + pad // 2))
    return img.resize((max(1, img.width // SUPERSAMPLE), max(1, img.height // SUPERSAMPLE)), Image.LANCZOS)


def _save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f"  {path.relative_to(ROOT)}  {img.width}x{img.height}")


def main():
    print("Icon (rounded navy tile):")
    for size in (1024, 512, 192, 180, 48):
        _save(render_mark(size), BRAND / f"tabmatch_icon_{size}.png")
    _save(render_mark(32), BRAND / "tabmatch_favicon_32.png")

    print("iOS icon (opaque, square; iOS rounds it itself):")
    _save(render_mark(1024, full_bleed=True).convert("RGB"), BRAND / "tabmatch_icon_ios_1024.png")

    print("Android adaptive layers (same shapes, no tile; the background is #0B1F3A):")
    _save(render_mark(1024, tile=False), BRAND / "tabmatch_icon_foreground_1024.png")
    _save(render_mark(1024, tile=False, mono=True), BRAND / "tabmatch_icon_monochrome_1024.png")

    print("Splash:")
    _save(render_mark(1152, tile=False, glyph_scale=0.7), BRAND / "tabmatch_splash_1152.png")

    print("Wordmark:")
    _save(render_wordmark(160, WHITE), BRAND / "tabmatch_wordmark_on_dark.png")
    _save(render_wordmark(160, NAVY), BRAND / "tabmatch_wordmark_on_light.png")

    print("Website:")
    _save(render_mark(32), SITE_IMAGES / "favicon-32.png")
    _save(render_mark(48), SITE_IMAGES / "favicon-48.png")
    _save(render_mark(180, full_bleed=True).convert("RGB"), SITE_IMAGES / "apple-touch-icon.png")
    social = Image.new("RGB", (1200, 630), NAVY)
    mark = render_mark(260)
    word = render_wordmark(150, WHITE)
    gap = 48
    total = mark.width + gap + word.width
    x = (1200 - total) // 2
    social.paste(mark, (x, (630 - mark.height) // 2), mark)
    social.paste(word, (x + mark.width + gap, (630 - word.height) // 2), word)
    _save(social, SITE_IMAGES / "og-image.png")


if __name__ == "__main__":
    main()
