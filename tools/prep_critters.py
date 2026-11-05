"""Turn the UI8 "3D Cute Animals" renders into game sprites.

Every view is trimmed to its visible pixels, scaled so all critters share one
height, and placed on a square cell with the feet on a shared ground line.

Usage: python3 tools/prep_critters.py [source_dir]   (default: source_art/ui8/animals/Characters)
Writes assets/critters/<name>/{front,back,left,right}.png
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(__file__)
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "source_art", "ui8", "animals", "Characters")
OUT = os.path.join(HERE, "..", "assets", "critters")
CELL = 256
GROUND = 252        # feet line inside each cell
HEIGHT = 236        # tallest view of each critter, in pixels
VIEWS = ("Front", "Back", "Left", "Right")


def trim(im: Image.Image) -> Image.Image:
    a = np.array(im)[..., 3]
    ys, xs = np.where(a > 10)
    return im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


for name in sorted(os.listdir(SRC)):
    folder = os.path.join(SRC, name)
    if not os.path.isdir(folder):
        continue
    views = {v: trim(Image.open(os.path.join(folder, v + ".png")).convert("RGBA")) for v in VIEWS}
    # One scale per critter keeps its views the same size as it turns.
    tallest = max(im.height for im in views.values())
    widest = max(im.width for im in views.values())
    scale = min(HEIGHT / tallest, (CELL - 8) / widest)
    dest = os.path.join(OUT, name.lower().replace(" ", "_"))
    os.makedirs(dest, exist_ok=True)
    for v, im in views.items():
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
        cell = Image.new("RGBA", (CELL, CELL))
        cell.alpha_composite(im, ((CELL - im.width) // 2, GROUND - im.height))
        cell.save(os.path.join(dest, v.lower() + ".png"))
    print(name, "->", dest)
