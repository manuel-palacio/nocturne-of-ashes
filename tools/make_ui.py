#!/usr/bin/env python3
"""Makes the interface's typefaces and its panel and button frames, in `assets/ui/`.

    uv run --python 3.12 --with fonttools==4.60.1 --with pillow==13.0.0 \
        python3 tools/make_ui.py fonts <Alegreya[wght].ttf> <PirataOne-Regular.ttf>
    uv run --python 3.12 --with fonttools==4.60.1 --with pillow==13.0.0 \
        python3 tools/make_ui.py frames

`fonts` takes Alegreya (The Alegreya Project Authors, a variable font) and Pirata One (Rodrigo
Fuenzalida and Nicolas Massi), both under the SIL Open Font License 1.1 (Google Fonts: ofl/alegreya,
ofl/pirataone, each with its `OFL.txt` beside it). It writes Alegreya at two fixed weights (medium
for text, bold for names and headings), cut down to the characters the game shows: Basic Latin,
Latin-1 (Spanish accents, ¿ ¡ « »), and the dashes, quotes and ellipsis; its layout features stay,
so `lnum` (lining figures) and kerning still work. Pirata One, a blackletter used for the game's
name only, is copied unchanged: its licence reserves the name "Pirata", so a cut-down copy could not
keep it. Both licences go beside them.

`frames` draws the frames of the panels and buttons: a dark, slightly mottled fill inside a thin
worn-iron edge, lit from the top left, with a rivet in each corner. Each is a small image for a
nine-patch (`StyleBoxTexture`): the corners stay as drawn and the edges and fill stretch.

The output is byte-identical from one run to the next for the pinned versions above (another
fontTools or Pillow can write the same fonts and images with other bytes). The fonts' timestamps
are kept as the source's, and the frames' noise comes from a fixed seed.
"""
import random
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets/ui"

# What the game shows: Basic Latin, Latin-1, the en and em dashes, curly quotes, the ellipsis.
UNICODES = (
    list(range(0x20, 0x7F))
    + list(range(0xA0, 0x100))
    + [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026]
)
TEXT_WEIGHTS = {"alegreya-medium.ttf": 500, "alegreya-bold.ttf": 700}
DISPLAY = "pirata-one.ttf"
LICENCE = "LICENSE-OFL-alegreya-pirata-one.txt"

# Frames: name -> (size, fill, edge light, edge shadow, rivet). Colours are RGBA.
FRAMES = {
    # The panels: party members, the dialogue box, the controls card.
    "panel": (32, (17, 13, 12, 232), (118, 110, 100, 255), (52, 47, 43, 255), (150, 140, 126, 255)),
    # A selected member's panel, or a Gift waiting for its target: a gilt edge.
    "panel_selected": (32, (34, 22, 15, 240), (226, 182, 96, 255), (128, 92, 40, 255), (246, 214, 140, 255)),
    "button": (32, (36, 27, 23, 240), (122, 114, 104, 255), (56, 50, 46, 255), (150, 140, 126, 255)),
    "button_hover": (32, (60, 38, 27, 245), (200, 162, 104, 255), (100, 76, 44, 255), (232, 200, 140, 255)),
    "button_pressed": (32, (24, 17, 14, 245), (84, 76, 68, 255), (120, 112, 102, 255), (120, 110, 98, 255)),
    "button_disabled": (32, (22, 19, 18, 200), (64, 60, 56, 255), (40, 37, 35, 255), (70, 66, 62, 255)),
}
SEED = 1212


def fonts(alegreya: str, pirata: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, weight in TEXT_WEIGHTS.items():
        font = TTFont(alegreya, recalcTimestamp=False)
        font = instancer.instantiateVariableFont(font, {"wght": weight}, updateFontNames=False)
        _subset_and_save(font, OUT / name)
    (OUT / DISPLAY).write_bytes(Path(pirata).read_bytes())
    print("wrote", (OUT / DISPLAY).relative_to(OUT.parent.parent))
    licence = Path(alegreya).with_name("OFL.txt").read_text(encoding="utf-8")
    pirata_licence = Path(pirata).with_name("OFL.txt").read_text(encoding="utf-8")
    header = (
        "Alegreya (assets/ui/alegreya-*.ttf, cut down to the characters the game shows by tools/make_ui.py)\n"
        "and Pirata One (assets/ui/pirata-one.ttf, unchanged) are used under the SIL Open Font License 1.1.\n\n"
        "=== Alegreya ===\n\n"
    )
    (OUT / LICENCE).write_text(header + licence + "\n=== Pirata One ===\n\n" + pirata_licence, encoding="utf-8")


def _subset_and_save(font: TTFont, path: Path) -> None:
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.recalc_timestamp = False
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=UNICODES)
    subsetter.subset(font)
    font.save(str(path))
    print("wrote", path.relative_to(OUT.parent.parent))


def frames() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (size, fill, light, shadow, rivet) in FRAMES.items():
        rng = random.Random(f"{SEED}-{name}")
        image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        pixels = image.load()
        last = size - 1
        for y in range(size):
            for x in range(size):
                edge = min(x, y, last - x, last - y)
                if edge == 0:
                    # The outermost ring: a near-black line that seats the frame on anything.
                    colour = (8, 6, 5, 255)
                elif edge <= 2:
                    # The iron: lit along the top and left, shadowed along the bottom and right, pitted.
                    lit = (x + y) < last if x + y != last else y < x
                    colour = _wear(light if lit else shadow, rng, 18 if edge == 1 else 26)
                elif edge == 3:
                    colour = (6, 5, 4, 255)
                else:
                    colour = _wear(fill, rng, 5)
                pixels[x, y] = colour
        for cx, cy in ((5, 5), (last - 5, 5), (5, last - 5), (last - 5, last - 5)):
            pixels[cx, cy] = rivet
            pixels[cx + 1, cy + 1] = (4, 3, 3, 255)
        path = OUT / f"{name}.png"
        image.save(path, optimize=False, compress_level=9)
        print("wrote", path.relative_to(OUT.parent.parent))


def _wear(colour: tuple, rng: random.Random, spread: int) -> tuple:
    shift = rng.randint(-spread, spread)
    r, g, b, a = colour
    return (_clamp(r + shift), _clamp(g + shift), _clamp(b + shift), a)


def _clamp(value: int) -> int:
    return max(0, min(255, value))


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "fonts":
        fonts(sys.argv[2], sys.argv[3])
    elif sys.argv[1:] == ["frames"]:
        frames()
    else:
        sys.exit(__doc__)
