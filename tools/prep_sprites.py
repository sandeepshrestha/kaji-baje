"""Slice the Kaji Baje sheets into equal frames, normalise every animation to
the same character height and put the feet on a shared ground line.

Usage: python3 tools/prep_sprites.py [source_dir]   (default: source_art/)
Writes assets/kaji_baje/<anim>.png (horizontal strips) + anims.json.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "source_art")
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "kaji_baje")
CELL = 256          # output frame size
GROUND = 248        # feet line inside each output frame

# A running pose is crouched, so matching heights would over-enlarge it.
CROUCH = {"run": 0.82}

# name: (file, columns, rows, fps, pixel_art)
ANIMS = {
    "idle": ("kaji_idle.png", 5, 5, 10, False),
    "walk": ("kaji_walk.png", 10, 1, 11, True),
    "run": ("kaji_run.png", 5, 5, 24, False),
}


def cells(path, cols, rows):
    im = Image.open(path).convert("RGBA")
    w, h = im.size[0] // cols, im.size[1] // rows
    return [im.crop((c * w, r * h, (c + 1) * w, (r + 1) * h)) for r in range(rows) for c in range(cols)]


def bbox(im):
    a = np.array(im)[..., 3]
    ys, xs = np.where(a > 10)
    return xs.min(), ys.min(), xs.max(), ys.max()


def main():
    os.makedirs(OUT, exist_ok=True)
    frames = {k: cells(os.path.join(SRC, v[0]), v[1], v[2]) for k, v in ANIMS.items()}
    heights = {k: float(np.median([bbox(f)[3] - bbox(f)[1] for f in fs])) for k, fs in frames.items()}
    target = heights["walk"]          # keep the pixel-art run at native scale
    meta = {}
    for name, fs in frames.items():
        scale = target / heights[name] * CROUCH.get(name, 1.0)
        pixel_art = ANIMS[name][4]
        ground = float(np.median([bbox(f)[3] for f in fs]))   # shared ground line keeps the run bounce
        strip = Image.new("RGBA", (CELL * len(fs), CELL), (0, 0, 0, 0))
        for i, f in enumerate(fs):
            x0, y0, x1, y1 = bbox(f)
            crop = f.crop((x0, y0, x1 + 1, y1 + 1))
            if abs(scale - 1.0) > 0.01:
                crop = crop.resize((max(1, round(crop.width * scale)), max(1, round(crop.height * scale))),
                                   Image.NEAREST if pixel_art else Image.LANCZOS)
            # Horizontal: centred; vertical: feet on GROUND.
            px = round(CELL / 2 - crop.width / 2)
            py = round(GROUND - (ground - y0) * scale)
            strip.alpha_composite(crop, (i * CELL + max(0, min(CELL - crop.width, px)), max(0, py)))
        strip.save(os.path.join(OUT, name + ".png"))
        meta[name] = {"frames": len(fs), "size": CELL, "fps": ANIMS[name][3], "ground": GROUND}
        print(f"{name}: {len(fs)} frames, scale {scale:.2f}")
    with open(os.path.join(OUT, "anims.json"), "w") as fh:
        json.dump(meta, fh, indent=1)


if __name__ == "__main__":
    main()
