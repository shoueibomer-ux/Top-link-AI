"""Regenerates the Android adaptive-icon layers from the TLA roundel.

    python tool/make_adaptive_icon.py

Why this exists: the launcher icon used to ship as a plain square PNG
(`mipmap-*/ic_launcher.png`), which Android 8+ does not treat as an adaptive
icon — it shrinks it into a light circular backdrop, drawing a ring around
the artwork. An adaptive icon supplies separate layers instead, which the
launcher masks itself (circle, squircle, ...):

  * background : solid navy (res/values/ic_launcher_background.xml)
  * foreground : the roundel, transparent around it
                 (mipmap-*/ic_launcher_foreground.png)
  * monochrome : the roundel's ink (letters + ring) as white-on-transparent,
                 tinted by Android 13+ "themed icons"
                 (mipmap-*/ic_launcher_monochrome.png)
  * the wiring : res/mipmap-anydpi-v26/ic_launcher.xml (written by hand, not
                 generated here)

Geometry (Android adaptive-icon spec): each layer is a 108dp canvas; the
launcher shows at most a centred 72dp circle, and only the inner 66dp is
guaranteed visible. The roundel is drawn 72dp wide so it fills a circular mask
edge to edge; its navy disc blends into the navy background, so on any other
mask shape it just sits on a matching navy field. The teal ring and letters
stay inside the 66dp safe zone.

Needs Pillow (`pip install pillow`) — a build-time tool only, not an app or
backend dependency.
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "images" / "toplinkai_icon.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

CANVAS_DP = 108
DISC_DP = 72
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}

# The roundel's navy disc — anything this colour is "background", not ink.
NAVY = (11, 31, 58)


def _ink_alpha(pixel) -> int:
    """0..255 for how much a roundel pixel is ink (white letters, teal L and
    ring) rather than the navy disc, keeping anti-aliased edges smooth."""
    r, g, b, a = pixel
    distance = max(abs(r - NAVY[0]), abs(g - NAVY[1]), abs(b - NAVY[2]))
    ink = min(1.0, max(0.0, (distance - 30) / 60))
    return round(a * ink)


def build(density: str, scale: float, source: Image.Image) -> None:
    canvas = round(CANVAS_DP * scale)
    disc = round(DISC_DP * scale)
    offset = ((canvas - disc) // 2,) * 2
    roundel = source.resize((disc, disc), Image.LANCZOS)

    # Opaque navy out to the canvas edge rather than transparent: the
    # foreground then carries its own background and never depends on the
    # background layer being composed underneath it. (Not needed for the
    # launcher's own light "ring" seen on the dock — that is Pixel Launcher's
    # predicted-app styling, present for any app in that slot; the icon
    # renders edge to edge everywhere else, e.g. in the all-apps list.)
    foreground = Image.new("RGBA", (canvas, canvas), NAVY + (255,))
    foreground.paste(roundel, offset, roundel)

    monochrome = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    ink = Image.new("RGBA", (disc, disc))
    src_px, ink_px = roundel.load(), ink.load()
    for y in range(disc):
        for x in range(disc):
            ink_px[x, y] = (255, 255, 255, _ink_alpha(src_px[x, y]))
    monochrome.paste(ink, offset, ink)

    folder = RES / f"mipmap-{density}"
    foreground.save(folder / "ic_launcher_foreground.png", optimize=True)
    monochrome.save(folder / "ic_launcher_monochrome.png", optimize=True)
    print(f"{density}: {canvas}px canvas, {disc}px roundel")


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    for density, scale in DENSITIES.items():
        build(density, scale, source)


if __name__ == "__main__":
    main()
