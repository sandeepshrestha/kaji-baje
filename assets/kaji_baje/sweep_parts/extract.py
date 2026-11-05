"""Cut the parts the sweep rig needs out of idle frame 0.

Writes into OUT (default: ../assets/kaji_baje/sweep_parts relative to this file's repo):
  body.png   idle frame 0 with the cane and the cane fist removed (holes patched)
  cane.png   the cane alone, occluded stretches rebuilt from clean wood rows
  fist.png   the cane fist alone
  sleeve.png the back-arm sleeve (shoulder cap to cuff), reused as the swinging arm
All parts keep frame coordinates (256x256) so the rig can use the idle anchor points directly.
"""
import os, sys
from PIL import Image, ImageDraw

SRC = sys.argv[1]
OUT = sys.argv[2]
os.makedirs(OUT, exist_ok=True)

idle = Image.open(SRC).convert("RGBA").crop((0, 0, 256, 256))
P = idle.load()
W = H = 256


def blank():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def poly_mask(pts):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m.load()


def is_shawl(c):
    r, g, b, a = c
    return (r - g > 85 and r > 140) or (b > r + 10)


CANE_AXIS = [(100, 162.5), (124, 161.5), (136, 161.0), (172, 159.5), (190, 158.0), (208, 155.0), (230, 153.5), (247, 152.0)]


def center(y):
    # cane axis measured on clean rows; the stick leans a little toward the feet
    for (y0, x0), (y1, x1) in zip(CANE_AXIS, CANE_AXIS[1:]):
        if y <= y1:
            t = max(0.0, (y - y0) / (y1 - y0))
            return x0 + (x1 - x0) * t
    return CANE_AXIS[-1][1]


# ---------------------------------------------------------------- cane
cane = blank()
C = cane.load()


def axis(y):
    # where the rebuilt cane puts its centre: one straight line, crook joint to ferrule
    return 162.5 + (y - 100) * (152.0 - 162.5) / 147.0


def copy_band(dst_y, src_y, drop_shawl=False):
    shift = round(axis(dst_y) - center(src_y))
    c = center(src_y)
    for x in range(round(c - 5), round(c + 7)):
        p = P[x, src_y]
        if p[3] == 0 or (drop_shawl and is_shawl(p)):
            continue
        C[x + shift, dst_y] = p


for y in range(70, 108):                       # crook
    for x in range(154, 192):
        if P[x, y][3]:
            C[x, y] = P[x, y]
for y in range(108, 138):                      # upper cord wrap + wood
    copy_band(y, y)
for y in range(138, 165):                      # behind the fist: reuse wood above it
    copy_band(y, 129 + (y - 138) % 9)
CANE_EDGE = P[158, 133]


def copy_right_half(dst_y, src_y):
    # left edge here is merged with the shawl outline: keep the wood, redraw the edge
    shift = round(axis(dst_y) - center(src_y))
    c = center(src_y)
    for x in range(round(c - 2), round(c + 6)):
        if P[x, src_y][3] and not is_shawl(P[x, src_y]):
            C[x + shift, dst_y] = P[x, src_y]
    C[round(axis(dst_y) - 3), dst_y] = CANE_EDGE


for y in range(165, 190):                      # beside the shawl edge
    copy_right_half(y, y)
for y in range(190, 204):                      # behind the shawl fringe
    copy_right_half(y, 168 + (y - 190))
for y in range(204, 237):                      # lower cord wrap + wood
    copy_band(y, y)
for y in range(237, 247):                      # tip, hidden by the sandal: extend and taper
    copy_band(y, 228 + (y - 237) % 8)
for y in range(243, 247):                      # round the ferrule
    c = axis(y); k = y - 242
    for x in range(round(c - 5), round(c + 7)):
        if x < c - 5 + k or x > c + 6 - k:
            C[x, y] = (0, 0, 0, 0)
        elif C[x, y][3]:
            r, g, b, a = C[x, y]
            C[x, y] = (int(r * .55), int(g * .5), int(b * .45), a)
cane.save(os.path.join(OUT, "cane.png"))

# ---------------------------------------------------------------- fist
FIST_POLY = [(152, 138), (167, 138), (172, 145), (172, 157), (168, 165), (152, 165)]
fm = poly_mask(FIST_POLY)
fist = blank(); F = fist.load()
for y in range(136, 167):
    for x in range(148, 174):
        p = P[x, y]
        if fm[x, y] and p[3] and not is_shawl(p):
            r, g, b, a = p
            wood = (r > 90 and 0.45 < g / max(r, 1) < 0.72 and b < 80 and x >= 158 and (y < 141 or y > 162))
            if not wood:
                F[x, y] = p
fist.save(os.path.join(OUT, "fist.png"))

# ---------------------------------------------------------------- body
body = idle.copy(); B = body.load()
cm = cane.load()
for y in range(70, 108):
    for x in range(154, 192):
        B[x, y] = (0, 0, 0, 0)
for y in range(108, 138):
    for x in range(153, 192):
        B[x, y] = (0, 0, 0, 0)
for y in range(136, 167):                      # fist + the cane under it
    for x in range(148, 192):
        if fm[x, y] or x >= 156:
            B[x, y] = (0, 0, 0, 0)
for y in range(167, 203):
    for x in range(157 if y < 190 else 158, 192):
        B[x, y] = (0, 0, 0, 0)

# The shawl's right edge ran under the fist and the cane: redraw it as a clean sloping hem.
OUTLINE = (52, 26, 20, 255)


def shawl_edge(y):
    return 151 + min(1.0, max(0.0, (y - 128) / 40.0)) * 5


for y in range(128, 190):
    e = round(shawl_edge(y))
    for x in range(146, 160):
        if x < e:
            if B[x, y][3] == 0 or (y >= 136 and x >= 148):
                B[x, y] = P[x - 7, y] if P[x - 7, y][3] else B[x - 1, y]
        else:
            B[x, y] = (0, 0, 0, 0)
    B[e - 1, y] = OUTLINE
    B[e - 2, y] = tuple(int(a * .6 + b * .4) for a, b in zip(B[e - 3, y], OUTLINE))
for y in range(203, 237):
    for x in range(148, 192):
        B[x, y] = (0, 0, 0, 0)
for y in range(237, 248):
    for x in range(157, 192):
        B[x, y] = (0, 0, 0, 0)
body.save(os.path.join(OUT, "body.png"))

# ---------------------------------------------------------------- sleeve
SLEEVE_POLY = [(84, 115), (103, 115), (106, 140), (105, 169), (77, 169), (69, 150), (74, 127)]
sm = poly_mask(SLEEVE_POLY)
sleeve = blank(); S = sleeve.load()
for y in range(112, 170):
    for x in range(66, 108):
        p = P[x, y]
        if sm[x, y] and p[3]:
            r, g, b, a = p
            navy = b > r - 5 and b > 60
            gold = r > 180 and g > 140 and b < 60
            skin = y >= 160 and r > 190 and 110 < g < 200 and b < 140 and r - b > 90
            if not navy and not gold and not skin and x <= 100:
                S[x, y] = p
for y in range(112, 170):                      # the vest side had no outline of its own
    xs = [x for x in range(66, 108) if S[x, y][3]]
    if xs:
        S[xs[-1] + 1, y] = OUTLINE
sleeve.save(os.path.join(OUT, "sleeve.png"))
print("ok")
