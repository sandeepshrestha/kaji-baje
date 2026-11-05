"""Build sweep.png from the painted 7-pose reference strip (sweep_reference.png).

The reference figures are ~191 px tall and the swing trails reach far past a
256 cell, so the sweep uses a wider, taller cell. Frames are centred on the
sprite origin in-engine, so the soles sit 120 px below the cell centre, the
same as the 256 cells (ground 248), and the back foot lands where idle's does.

    python3 assets/kaji_baje/sweep_parts/from_reference.py
"""
from collections import deque
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SRC = HERE / "sweep_reference.png"
OUT = HERE.parent / "sweep.png"

CELL_W, CELL_H = 416, 288
SOLE_Y = CELL_H // 2 + 122          # idle soles are at 250 in a 256 cell
BACK_FOOT_X = CELL_W // 2 - 28      # idle back foot centre is 28 px left of centre
SCALE = 226.0 / 191.0               # idle topi-to-sole height / reference height

# Source x of each pose's back-foot centre; all soles rest on y=280.
BACK_FOOT = [50, 178, 300.5, 424.5, 610.5, 784, 931.5]
SRC_SOLE_Y = 280


def components(img):
    px = img.load()
    w, h = img.size
    seen = bytearray(w * h)
    comps = []
    for y in range(h):
        for x in range(w):
            if seen[y * w + x] or px[x, y][3] <= 8:
                continue
            q = deque([(x, y)])
            seen[y * w + x] = 1
            pts = []
            while q:
                cx, cy = q.popleft()
                pts.append((cx, cy))
                for nx in (cx - 1, cx, cx + 1):
                    for ny in (cy - 1, cy, cy + 1):
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny][3] > 8:
                            seen[ny * w + nx] = 1
                            q.append((nx, ny))
            comps.append(pts)
    return comps


def owner(x, y, cx):
    # The strike's swing trail touches the impact pose's back sandal, so those
    # two poses arrive as one shape (centroid ~574) and are split by hand.
    if 500 < cx < 650:
        return 3 if x < 596 or (x < 619 and y < 245) else 4
    return min(range(len(BACK_FOOT)), key=lambda i: abs(BACK_FOOT[i] + 30 - cx))


def main():
    src = Image.open(SRC).convert("RGBA")
    spx = src.load()
    layers = [Image.new("RGBA", src.size, (0, 0, 0, 0)) for _ in BACK_FOOT]
    lpx = [l.load() for l in layers]
    for pts in components(src):
        cx = sum(p[0] for p in pts) / len(pts)
        for x, y in pts:
            lpx[owner(x, y, cx)][x, y] = spx[x, y]

    strip = Image.new("RGBA", (CELL_W * len(layers), CELL_H), (0, 0, 0, 0))
    for i, layer in enumerate(layers):
        box = layer.getbbox()
        part = layer.crop(box)
        part = part.resize((round(part.width * SCALE), round(part.height * SCALE)), Image.LANCZOS)
        ox = BACK_FOOT_X - (BACK_FOOT[i] - box[0]) * SCALE
        oy = SOLE_Y - (SRC_SOLE_Y - box[1]) * SCALE
        x, y = round(i * CELL_W + ox), round(oy)
        assert x >= i * CELL_W and x + part.width <= (i + 1) * CELL_W, f"pose {i} overflows its cell"
        assert y >= 0 and y + part.height <= CELL_H, f"pose {i} overflows vertically"
        strip.alpha_composite(part, (x, y))
    strip.save(OUT)
    print("wrote", OUT, strip.size)


if __name__ == "__main__":
    main()
