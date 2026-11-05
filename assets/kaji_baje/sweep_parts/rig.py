"""Pose the parts cut by extract.py into the cane-sweep strip.

usage: python3 rig.py PARTS_DIR FX_DIR OUT_PNG [PREVIEW_DIR IDLE_PNG]
  FX_DIR holds pxl's anims/sweep_fx_{back,mid,top}.png

Rebuild assets/kaji_baje/sweep.png (from assets/kaji_baje):
  python3 sweep_parts/extract.py idle.png sweep_parts          # body/cane/fist/sleeve.png
  node <pxl>/bin/pxl.js build sweep.px.js --out sweep_parts/fx  # smear, glint, dust
  python3 sweep_parts/rig.py sweep_parts sweep_parts/fx sweep.png [/tmp/preview idle.png]
rig.py prints each frame's fist and cane tip; sweep.px.js keeps a copy of them (CANE) so the
smears follow the stick. Frame times (ms) go to anims.json as "durations" (multiples of 1/fps).

Every frame is built from the real idle-frame-0 pixels:
  legs   stay planted (feet on y=248); the knees can be pushed forward a few px
  upper  head + torso + shawl, rotated about the hip and shifted (lean / crouch)
  sleeve the near arm, stretched from the shoulder to the wrist (optionally via an elbow)
  fist + cane rotate together around the grip; the grip can slide toward the crook
  fx     smear / glint / dust frames rendered by pxl from sweep.px.js, composited last
crack_rig.py imports this module (parts, body split, placement, outputs) for the overhead crack.
"""
import json, math, os, sys
from PIL import Image, ImageDraw

PARTS = sys.argv[1] if __name__ == "__main__" else os.path.dirname(os.path.abspath(__file__))
W = H = 256
GROUND = 248

HIP = (122, 200)            # upper-body pivot
SHOULDER = (146, 124)       # near shoulder, under the shawl
FIST_C = (161, 151)         # fist centre == idle grip on the cane
WRIST = (-9, 2)             # wrist side of the fist, relative to FIST_C
SLEEVE_TOP, SLEEVE_CUFF = (91, 117), (89, 168)
CANE_TOP, CANE_TIP = 76, 246


def axis_x(y):
    return 162.5 + (y - 100) * (152.0 - 162.5) / 147.0


# x, y: fist centre.  rot: cane angle vs idle, clockwise.  grip: cane row held.
# fore: cane foreshortening.  lean/dx/dy: upper body.  knee/rknee: front/rear knee push.
# shawl/tail/beard: secondary lag in px.  behind: cane passes behind the body.
# elbow: optional elbow point for a bent arm.  ms: frame time.
POSES = [
    dict(ms=60,  x=152, y=136, rot=40,  grip=138, fore=1.0, lean=-3, dx=-2, dy=2, knee=0, rknee=2,
         barm=-4, shawl=2, tail=2, beard=1, behind=True, tuck=True),
    dict(ms=120, x=142, y=110, rot=128, grip=120, fore=1.0, lean=-7, dx=-4, dy=3, knee=-1, rknee=3,
         barm=-10, shawl=4, tail=4, beard=2, behind=True, elbow=(168, 136)),
    dict(ms=40,  x=180, y=102, rot=215, grip=118, fore=0.58, lean=4, dx=1, dy=3, knee=2, rknee=0,
         barm=0, shawl=0, tail=1, beard=0, behind=False),
    dict(ms=60,  x=200, y=140, rot=-34, grip=118, fore=0.71, lean=10, dx=2, dy=6, knee=5, rknee=-1,
         barm=8, shawl=-4, tail=-4, beard=-2, behind=False),
    dict(ms=70,  x=190, y=168, rot=8,   grip=120, fore=0.80, lean=11, dx=3, dy=7, knee=5, rknee=-1,
         barm=7, shawl=4, tail=-1, beard=2, behind=False),
    dict(ms=90,  x=174, y=158, rot=-6,  grip=134, fore=1.0, lean=5, dx=1, dy=3, knee=2, rknee=0,
         barm=3, shawl=2, tail=1, beard=1, behind=False, tuck=True),
    dict(ms=90,  x=162, y=151, rot=-1,  grip=151, fore=1.0, lean=1, dx=0, dy=1, knee=1, rknee=0,
         barm=1, shawl=1, tail=0, beard=0, behind=False, tuck=True),
]


def load(n):
    return Image.open(os.path.join(PARTS, n + ".png")).convert("RGBA")


body, cane, fist, sleeve = load("body"), load("cane"), load("fist"), load("sleeve")


def rot(v, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def place(img, anchor, target, deg=0.0, sx=1.0, sy=1.0):
    """Map img so `anchor` lands on `target`, rotated `deg` clockwise, scaled sx/sy in its own frame."""
    if deg == 0 and sx == 1 and sy == 1 and all(float(a - t).is_integer() for a, t in zip(anchor, target)):
        out = Image.new("RGBA", (W, H))
        out.alpha_composite(img, (0, 0)) if anchor == target else out.paste(img, (round(target[0] - anchor[0]), round(target[1] - anchor[1])), img)
        return out
    # inverse: p = A + S^-1 R(-deg) (q - T)
    a = math.radians(-deg)
    c, s = math.cos(a), math.sin(a)
    m = (c / sx, -s / sx, 0, s / sy, c / sy, 0)
    tx, ty = target
    coeffs = (m[0], m[1], anchor[0] - m[0] * tx - m[1] * ty,
              m[3], m[4], anchor[1] - m[3] * tx - m[4] * ty)
    pm = img.convert("RGBa").transform((W, H), Image.AFFINE, coeffs, resample=Image.BICUBIC)
    return pm.convert("RGBA")


def poly_mask(pts):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m.load()


BACK_ARM = poly_mask([(70, 114), (103, 114), (107, 140), (109, 195), (79, 195), (71, 182), (64, 150)])
BACK_SHOULDER = (92, 121)


def torso_left(y):
    # left contour of vest/tunic hidden behind the back arm
    pts = [(110, 92), (170, 90), (190, 84), (200, 84)]
    for (y0, x0), (y1, x1) in zip(pts, pts[1:]):
        if y <= y1:
            return x0 + (x1 - x0) * max(0.0, (y - y0) / (y1 - y0))
    return pts[-1][1]
SHAWL = poly_mask([(137, 112), (151, 110), (158, 140), (160, 204), (139, 204), (136, 150)])
B = body.load()


def split_body(p):
    """Return (upper, legs) images with the shawl/beard lag and knee pushes applied."""
    upper, legs = Image.new("RGBA", (W, H)), Image.new("RGBA", (W, H))
    U, L = upper.load(), legs.load()
    for y in range(H):
        for x in range(W):
            px = B[x, y]
            if not px[3]:
                continue
            tail = x < 94 and y < 216
            if y < 204 or tail:
                U[x, y] = px
            if y >= 198 and not tail:
                L[x, y] = px
    for x in range(96, 151):                 # trouser cloth under the hem, shows if the hem lifts
        src = B[x, 209]
        if src[3]:
            for y in range(186, 205):
                if not L[x, y][3]:
                    L[x, y] = src
    # knees: shear the trouser legs, feet stay put
    for name, x0, x1 in (("knee", 118, 160), ("rknee", 84, 118)):
        k = p.get(name, 0)
        if not k:
            continue
        src = legs.copy().load()
        for y in range(186, 232):
            d = round(k * min(1.0, (232 - y) / 30.0))
            if not d:
                continue
            for x in range(x0, x1):
                L[x, y] = (0, 0, 0, 0)
            for x in range(x0, x1):
                if src[x, y][3] and x0 <= x + d < x1 + 6:
                    L[x + d, y] = src[x, y]
    # back arm counter-swing: lift it out, patch the vest/tunic behind it, rotate about the shoulder
    swing = p.get("barm", 0)
    if swing:
        arm = Image.new("RGBA", (W, H))
        A = arm.load()
        src = upper.copy().load()
        for y in range(110, 200):
            for x in range(60, 112):
                c = src[x, y]
                if BACK_ARM[x, y] and c[3] and not (c[0] - c[1] > 85 and c[0] > 140) and not (c[2] > c[0] - 5 and c[2] > 60) and (y < 181 or x > 84 or (c[0] > 170 and c[1] > 110 and c[0] - c[2] > 60)) and not (c[0] > 180 and c[1] > 140 and c[2] < 60):
                    A[x, y] = c
        for y in range(110, 200):
            inside = torso_left(y)
            for x in range(60, 112):
                if not A[x, y][3]:
                    continue
                if x < inside:
                    U[x, y] = (0, 0, 0, 0)
                    continue
                k = x
                while k < 139 and A[k, y][3]:
                    k += 1
                U[x, y] = src[k + 1, y]
        U_img = place(arm, BACK_SHOULDER, BACK_SHOULDER, swing)
        upper.alpha_composite(U_img)
        U = upper.load()
    # front shawl panel lag
    lag = p.get("shawl", 0)
    if lag:
        src = upper.copy().load()
        for y in range(112, 205):
            d = round(lag * max(0.0, (y - 125) / 79.0) ** 1.5)
            if not d:
                continue
            row = [(x, src[x, y]) for x in range(128, 170) if SHAWL[x, y] and src[x, y][3]]
            if not row:
                continue
            left = row[0][0]
            for x, _ in row:
                U[x, y] = src[left - 3, y] if d > 0 and x < left + d else (0, 0, 0, 0)
            for x, c in row:
                U[x + d, y] = c
    # back shawl tail lag
    lag = p.get("tail", 0)
    if lag:
        src = upper.copy().load()
        for y in range(190, 216):
            d = round(lag * (y - 190) / 26.0)
            row = [(x, src[x, y]) for x in range(55, 94)]
            for x, _ in row:
                U[x, y] = (0, 0, 0, 0)
            for x, c in row:
                if c[3]:
                    U[x + d, y] = c
    # beard tip trails the head
    lag = p.get("beard", 0)
    if lag:
        src = upper.copy().load()
        for y in range(96, 124):
            d = round(lag * (y - 96) / 28.0)
            if not d:
                continue
            for x in range(100, 160):
                r, g, b, a = src[x, y]
                if a > 200 and min(r, g, b) > 185 and max(r, g, b) - min(r, g, b) < 40:
                    U[x + d, y] = src[x, y]
    return upper, legs


def body_xf(pt, p):
    v = rot((pt[0] - HIP[0], pt[1] - HIP[1]), p["lean"])
    return (HIP[0] + v[0] + p["dx"], HIP[1] + v[1] + p["dy"])


def sleeve_segment(y0, y1):
    seg = Image.new("RGBA", (W, H))
    seg.paste(sleeve.crop((0, y0, W, y1)), (0, y0))
    return seg


SLEEVE_UP = sleeve_segment(112, 144)
SLEEVE_LO = sleeve_segment(138, 172)


def limb(img, a_src, b_src, a, b, width=0.95):
    d = (b[0] - a[0], b[1] - a[1])
    length = math.hypot(*d)
    deg = math.degrees(math.atan2(-d[0], d[1]))
    src_len = math.hypot(b_src[0] - a_src[0], b_src[1] - a_src[1])
    src_deg = math.degrees(math.atan2(-(b_src[0] - a_src[0]), b_src[1] - a_src[1]))
    return place(img, a_src, a, deg - src_deg, width, max(0.45, length / src_len))


def angdiff(a, b):
    return abs((a - b + 180) % 360 - 180)


def render(p, fx_back=None, fx_mid=None):
    upper_raw, legs = split_body(p)
    upper = place(upper_raw, HIP, (HIP[0] + p["dx"], HIP[1] + p["dy"]), p["lean"])
    shoulder = body_xf(SHOULDER, p)
    F = (p["x"], p["y"])
    theta = p["rot"]

    # cane: rotate about the grip, foreshorten along its own axis, keep the tip above ground
    grip = (axis_x(p["grip"]), p["grip"])
    fore = p["fore"]
    tip_dir = rot((0, 1), theta)
    if tip_dir[1] > 0:
        fore = min(fore, (GROUND - 2 - F[1]) / (tip_dir[1] * (CANE_TIP - p["grip"])))
    cane_img = place(cane, grip, F, theta, 1.0, fore)
    tip = (F[0] + tip_dir[0] * (CANE_TIP - p["grip"]) * fore, F[1] + tip_dir[1] * (CANE_TIP - p["grip"]) * fore)

    # fist: same line as the cane (either way round), turned toward the forearm
    toward = p.get("elbow") or shoulder
    want = math.degrees(math.atan2(toward[1] - F[1], toward[0] - F[0]))
    best = None
    for base in (theta, theta + 180):
        for k in range(-30, 31, 2):
            d = rot(WRIST, base + k)
            err = angdiff(math.degrees(math.atan2(d[1], d[0])), want) + abs(k) * 0.4
            if best is None or err < best[0]:
                best = (err, base + k)
    theta_f = best[1]
    fist_img = place(fist, FIST_C, F, theta_f)
    w = rot(WRIST, theta_f)
    wrist = (F[0] + w[0] * 0.8, F[1] + w[1] * 0.8)

    if p.get("elbow"):
        e = p["elbow"]
        arm = [limb(SLEEVE_UP, SLEEVE_TOP, (90, 141), shoulder, e),
               limb(SLEEVE_LO, (90, 140), SLEEVE_CUFF, e, wrist)]
    else:
        arm = [limb(sleeve, SLEEVE_TOP, SLEEVE_CUFF, shoulder, wrist)]

    # shawl drape over the shoulder stays on top of the upper arm
    cap = Image.new("RGBA", (W, H))
    if p.get("tuck"):
        cap_mask = poly_mask([(132, 104), (156, 104), (162, 140), (166, 206), (136, 206), (132, 124)])
    else:
        cap_mask = poly_mask([(132, 104), (156, 104), (158, 132), (138, 140), (132, 124)])
    cu, U0 = cap.load(), upper_raw.load()
    for y in range(100, 208):
        for x in range(128, 170):
            if cap_mask[x, y]:
                cu[x, y] = U0[x, y]
    cap = place(cap, HIP, (HIP[0] + p["dx"], HIP[1] + p["dy"]), p["lean"])

    frame = Image.new("RGBA", (W, H))
    if fx_back is not None:
        frame.alpha_composite(fx_back)
    if p["behind"]:
        frame.alpha_composite(cane_img)
    frame.alpha_composite(legs)
    frame.alpha_composite(upper)
    if fx_mid is not None:
        frame.alpha_composite(fx_mid)
    for a in arm:
        frame.alpha_composite(a)
    frame.alpha_composite(cap)
    if not p["behind"]:
        frame.alpha_composite(cane_img)
    frame.alpha_composite(fist_img)
    return frame, dict(tip=[round(tip[0]), round(tip[1])], fist=list(F), shoulder=[round(shoulder[0]), round(shoulder[1])])


def fx_strip(fx_dir, name):
    path = os.path.join(fx_dir, "anims", name + ".png")
    return Image.open(path).convert("RGBA") if os.path.exists(path) else None


def cell(strip, i):
    return strip.crop((i * W, 0, (i + 1) * W, H)) if strip is not None and strip.width >= (i + 1) * W else None


def write_outputs(name, frames, ms, out, preview=None, idle_png=None):
    """Save the strip, and optionally <name>_contact.png / _contact_2x.png / _preview.gif framed by idle."""
    strip = Image.new("RGBA", (W * len(frames), H))
    for i, f in enumerate(frames):
        strip.paste(f, (i * W, 0))
    strip.save(out)
    if not preview:
        return
    os.makedirs(preview, exist_ok=True)
    idle = Image.open(idle_png).convert("RGBA").crop((0, 0, W, H)) if idle_png else None
    seq = ([idle] if idle else []) + frames + ([idle] if idle else [])
    bg = (74, 92, 78, 255)
    sheet = Image.new("RGBA", (W * len(seq), H + 14), bg)
    d = ImageDraw.Draw(sheet)
    for i, f in enumerate(seq):
        sheet.alpha_composite(f, (i * W, 0))
        d.line([(i * W, GROUND), (i * W + W - 1, GROUND)], fill=(50, 60, 52, 255))
        lab = "idle" if (idle and (i == 0 or i == len(seq) - 1)) else "f%d %dms" % (i - (1 if idle else 0), ms[i - (1 if idle else 0)])
        d.text((i * W + 4, H + 2), lab, fill=(255, 227, 154, 255))
    sheet.save(os.path.join(preview, name + "_contact.png"))
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(os.path.join(preview, name + "_contact_2x.png"))
    gif = []
    durs = []
    for f, t in ([(idle, 400)] if idle else []) + list(zip(frames, ms)) + ([(idle, 500)] if idle else []):
        g = Image.new("RGBA", (W, H), bg)
        g.alpha_composite(f)
        gif.append(g.resize((W * 2, H * 2), Image.NEAREST).convert("RGB"))
        durs.append(t)
    gif[0].save(os.path.join(preview, name + "_preview.gif"), save_all=True, append_images=gif[1:], duration=durs, loop=0)


def main():
    fx_dir, out = sys.argv[2:4]
    preview = sys.argv[4] if len(sys.argv) > 4 else None
    fx_back, fx_mid, fx_top = (fx_strip(fx_dir, "sweep_fx_" + n) for n in ("back", "mid", "top"))
    frames, info = [], []
    for i, p in enumerate(POSES):
        f, meta = render(p, cell(fx_back, i), cell(fx_mid, i))
        top = cell(fx_top, i)
        if top is not None:
            f.alpha_composite(top)
        frames.append(f)
        info.append(meta)
    write_outputs("sweep", frames, [p["ms"] for p in POSES], out, preview, sys.argv[5] if len(sys.argv) > 5 else None)
    print(json.dumps({"ms": [p["ms"] for p in POSES], "frames": info}))


if __name__ == "__main__":
    main()
