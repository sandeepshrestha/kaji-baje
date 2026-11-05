"""Build idle.png from the painted 6-frame breathing loop.

    python3 assets/kaji_baje/sweep_parts/idle_from_reference.py

The cell stays 256 with the sole on y=248, which is what the game uses to
place every other animation. The back foot sits at x=100, matching the
original idle.
"""
from collections import deque
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SRC = HERE / "idle_reference.png"
OUT = HERE.parent / "idle.png"

CELL = 256
SOLE_Y = 246
BODY_X = 128
# Original idle topi-to-sole is 224 px; these poses are 360.
SCALE = 224.0 / 360.0


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
            if len(pts) > 500:
                comps.append(pts)
    comps.sort(key=lambda pts: min(p[0] for p in pts))
    return comps


def back_foot(px, pts):
    y1 = max(p[1] for p in pts)
    brown = [p for p in pts if p[1] > y1 - 24 and px[p][3] > 140 and px[p][0] > 90 and px[p][2] < 90]
    xs = sorted({p[0] for p in brown})
    clusters, cur = [], [xs[0]]
    for a, b in zip(xs, xs[1:]):
        if b - a > 6:
            clusters.append(cur)
            cur = [b]
        else:
            cur.append(b)
    clusters.append(cur)
    foot = clusters[0]
    sole = max(p[1] for p in brown if p[0] in foot)
    return sum(foot) / len(foot), sole


def main():
    src = Image.open(SRC).convert("RGBA")
    spx = src.load()
    poses = components(src)
    if len(poses) != 6:
        raise SystemExit(f"expected 6 poses, found {len(poses)}")
    strip = Image.new("RGBA", (CELL * 6, CELL), (0, 0, 0, 0))
    for i, pts in enumerate(poses):
        layer = Image.new("RGBA", src.size, (0, 0, 0, 0))
        lp = layer.load()
        for x, y in pts:
            lp[x, y] = spx[x, y]
        _foot_x, sole_y = back_foot(spx, pts)
        box = layer.getbbox()
        part = layer.crop(box)
        part = part.resize((round(part.width * SCALE), round(part.height * SCALE)), Image.LANCZOS)
        ox = BODY_X - part.width / 2.0
        oy = SOLE_Y - (sole_y - box[1]) * SCALE
        x, y = round(i * CELL + ox), round(oy)
        if x < i * CELL or x + part.width > (i + 1) * CELL or y < 0 or y + part.height > CELL:
            raise SystemExit(f"pose {i} does not fit ({part.size} at {x % CELL},{y})")
        strip.alpha_composite(part, (x, y))
    strip.save(OUT)
    print("wrote", OUT, strip.size)


if __name__ == "__main__":
    main()
