"""Pose the sweep parts into the two-handed overhead crack strip.

usage: python3 crack_rig.py FX_DIR OUT_PNG [PREVIEW_DIR IDLE_PNG]
  FX_DIR holds pxl's anims/crack_fx_{back,mid,top}.png

Rebuild assets/kaji_baje/crack.png (from assets/kaji_baje):
  python3 sweep_parts/extract.py idle.png sweep_parts          # body/cane/fist/sleeve.png (shared with the sweep)
  node <pxl>/bin/pxl.js build crack.px.js --out sweep_parts/fx  # smear, spark, crack, dust
  python3 sweep_parts/crack_rig.py sweep_parts/fx crack.png [/tmp/crack_preview idle.png]
Prints each frame's fist and cane tip; crack.px.js keeps a copy of them (CANE).

Same parts and helpers as rig.py (the sweep). What the crack adds:
  two    both hands on the cane: the idle back arm is lifted off the torso and replaced by a
         darker far arm (the sleeve part) reaching a second, darker fist `gap` px down the stick
  reach  the near arm starts behind the beard and is drawn under the body, so a raised arm
         shows beside the head instead of across the face
"""
import json, math, os, sys
from PIL import Image

import rig
from rig import (W, H, GROUND, HIP, SHOULDER, FIST_C, WRIST, SLEEVE_TOP, SLEEVE_CUFF, CANE_TIP,
                 axis_x, place, poly_mask, rot, split_body, body_xf, limb, angdiff,
                 SLEEVE_UP, SLEEVE_LO, BACK_ARM, torso_left)

FAR_SHOULDER = (114, 124)   # far shoulder, hidden behind the torso
ARM_ROOT = (148, 108)       # near shoulder seen from behind the beard (raised arm)
OUTLINE = (52, 26, 20, 255)

# Shared keys as rig.py POSES, plus:
#   two: second hand on the cane, `gap` px toward the tip.  belbow: optional far-arm elbow.
#   reach: near arm drawn under the body from ARM_ROOT.  barm: idle back arm swing (one-handed).
POSES = [
    # 0 lift: both hands take the cane to the chest, tip drops behind the legs, weight back
    dict(ms=100, x=170, y=122, rot=36,  grip=122, gap=20, fore=1.0, lean=-3, dx=-2, dy=2, knee=0, rknee=2,
         shawl=2, tail=2, beard=1, behind=True, tuck=True, two=True, elbow=(158, 148)),
    # 1 rising: hands pass the face, cane tips back over the shoulder
    dict(ms=110, x=180, y=98,  rot=60,  grip=118, gap=20, fore=1.0, lean=-6, dx=-3, dy=2, knee=-1, rknee=3,
         shawl=3, tail=3, beard=2, behind=True, two=True),
    # 2 peak: cane cocked behind the head, longest hold (he is open here)
    dict(ms=240, x=162, y=56,  rot=84,  grip=116, gap=20, fore=1.0, lean=-9, dx=-4, dy=3, knee=-1, rknee=3,
         shawl=4, tail=4, beard=3, behind=True, two=True, reach=True),
    # 3 whip: over the top and forward, smeared
    dict(ms=40,  x=194, y=72,  rot=238, grip=116, gap=20, fore=0.46, lean=6, dx=2, dy=4, knee=3, rknee=0,
         shawl=-3, tail=-3, beard=-2, behind=False, two=True),
    # 4 strike: coming down in front, smeared
    dict(ms=40,  x=198, y=98,  rot=322, grip=116, gap=20, fore=0.62, lean=9, dx=3, dy=6, knee=4, rknee=-1,
         shawl=-4, tail=-3, beard=-2, behind=False, two=True),
    # 5 impact: stick upright in front of the front foot, body dropped into it
    dict(ms=100, x=198, y=118, rot=3,   grip=116, gap=20, fore=1.0, lean=11, dx=3, dy=8, knee=6, rknee=-1,
         shawl=5, tail=2, beard=3, behind=False, two=True),
    # 6 rebound: tip jumps off the ground
    dict(ms=70,  x=196, y=110, rot=1,   grip=116, gap=20, fore=0.95, lean=9, dx=2, dy=6, knee=5, rknee=-1,
         shawl=2, tail=1, beard=1, behind=False, two=True),
    # 7 recover: back hand lets go, stick comes home
    dict(ms=90,  x=174, y=150, rot=-5,  grip=132, fore=1.0, lean=4, dx=1, dy=3, knee=2, rknee=0,
         barm=6, shawl=-1, tail=1, beard=1, behind=False, tuck=True),
    # 8 settle: matches idle frame 0
    dict(ms=90,  x=162, y=151, rot=-1,  grip=151, fore=1.0, lean=1, dx=0, dy=1, knee=1, rknee=0,
         barm=1, shawl=1, tail=0, beard=0, behind=False, tuck=True),
]


def shade(img, k):
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r.point(lambda v: int(v * k)), g.point(lambda v: int(v * k)),
                                b.point(lambda v: int(min(255, v * k * 1.06))), a))


def knuckles(img):
    """The fist's finger block only: its dark cuff/shadow column reads as noise on the far hand."""
    out = Image.new("RGBA", (W, H))
    src, dst = img.load(), out.load()
    for y in range(H):
        for x in range(157, W):
            dst[x, y] = src[x, y]
    for y in range(H):
        for x in range(157, W):
            if dst[x, y][3] and not dst[x - 1, y][3]:
                dst[x - 1, y] = OUTLINE
    return out


def cloth_only(img):
    """Sleeve without its dark outline: only slivers of the far arm show, and outline slivers read as stray lines."""
    out = img.copy()
    px = out.load()
    for y in range(H):
        for x in range(W):
            if px[x, y][3] and max(px[x, y][:3]) < 110:
                px[x, y] = (0, 0, 0, 0)
    return out


FAR_FIST, FAR_SLEEVE = shade(knuckles(rig.fist), 0.84), shade(cloth_only(rig.sleeve), 0.74)


def lift_back_arm(upper):
    """Take the idle back arm (sleeve and hand) off the torso. The vest/tunic it covered is rebuilt by
    repeating the strip just right of the arm, with an outline on the torso's back edge."""
    U = upper.load()
    src = upper.copy().load()
    navy = lambda c: c[2] > c[0] - 5 and c[2] > 60
    gold = lambda c: c[0] > 180 and c[1] > 140 and c[2] < 60
    shawl = lambda c, y: y >= 184 and c[0] - c[1] > 100 and c[1] < 90 and c[2] < 90
    A = {(x, y) for y in range(110, 200) for x in range(60, 112)
         if BACK_ARM[x, y] and src[x, y][3] and not navy(src[x, y]) and not gold(src[x, y]) and not shawl(src[x, y], y)}
    for y in range(110, 184):                      # arm edge pixels outside the mask
        for x in range(60, round(torso_left(y)) + 2):
            U[x, y] = (0, 0, 0, 0)
    for y in range(110, 200):
        row = [x for x in range(60, 112) if (x, y) in A]
        if not row:
            continue
        inside = round(torso_left(y)) + 2
        k = max(row) + 1
        strip = [src[x, y] for x in range(k + 1, k + 9) if src[x, y][3] and not gold(src[x, y])]
        strip = sorted([c for c in strip if navy(c) and y < 172] or strip, key=sum)
        base = strip[len(strip) // 2] if strip else None
        for x in row:
            if x < inside or base is None:
                U[x, y] = (0, 0, 0, 0)
                continue
            s = min(1.0, 0.8 + 0.05 * (x - inside))          # turns away into shadow at the back edge
            U[x, y] = (int(base[0] * s), int(base[1] * s), int(base[2] * min(1.0, s + 0.04)), 255)
        if base is not None and inside <= k:
            U[inside, y] = OUTLINE
    # specks of hand shadow left over the shawl tail
    for _ in range(2):
        snap = upper.copy().load()
        for y in range(176, 204):
            for x in range(60, 100):
                if snap[x, y][3] and sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if snap[x + dx, y + dy][3]) < 2:
                    U[x, y] = (0, 0, 0, 0)
    seen = set()
    for y in range(176, 204):
        for x in range(60, 100):
            if (x, y) in seen or not U[x, y][3]:
                continue
            blob, todo = [], [(x, y)]
            seen.add((x, y))
            while todo:
                cx, cy = todo.pop()
                blob.append((cx, cy))
                for n in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if n not in seen and 0 <= n[0] < W and 0 <= n[1] < H and U[n][3]:
                        seen.add(n)
                        todo.append(n)
            if len(blob) < 30:
                for q in blob:
                    U[q] = (0, 0, 0, 0)


def grip_fist(img, F, theta, toward):
    """Fist on the cane line (either way round), turned toward its forearm. Returns (image, wrist)."""
    want = math.degrees(math.atan2(toward[1] - F[1], toward[0] - F[0]))
    best = None
    for base in (theta, theta + 180):
        for k in range(-30, 31, 2):
            d = rot(WRIST, base + k)
            err = angdiff(math.degrees(math.atan2(d[1], d[0])), want) + abs(k) * 0.4
            if best is None or err < best[0]:
                best = (err, base + k)
    w = rot(WRIST, best[1])
    return place(img, FIST_C, F, best[1]), (F[0] + w[0] * 0.8, F[1] + w[1] * 0.8)


def arm(sleeve_up, sleeve_lo, sleeve_all, root, elbow, wrist):
    if elbow:
        return [limb(sleeve_up, SLEEVE_TOP, (90, 141), root, elbow), limb(sleeve_lo, (90, 140), SLEEVE_CUFF, elbow, wrist)]
    return [limb(sleeve_all, SLEEVE_TOP, SLEEVE_CUFF, root, wrist)]


def crop_rows(img, y0, y1):
    seg = Image.new("RGBA", (W, H))
    seg.paste(img.crop((0, y0, W, y1)), (0, y0))
    return seg


FAR_UP, FAR_LO = crop_rows(FAR_SLEEVE, 112, 144), crop_rows(FAR_SLEEVE, 138, 172)


def render(p, fx_back=None, fx_mid=None):
    q = dict(p)
    if p.get("two"):
        q["barm"] = 0
    upper_raw, legs = split_body(q)
    if p.get("two"):
        lift_back_arm(upper_raw)
    upper = place(upper_raw, HIP, (HIP[0] + p["dx"], HIP[1] + p["dy"]), p["lean"])
    F = (p["x"], p["y"])
    theta = p["rot"]

    # the cane part leans a little in idle, so follow its real axis to the ferrule
    grip = (axis_x(p["grip"]), p["grip"])
    along = (axis_x(CANE_TIP) - grip[0], CANE_TIP - grip[1])
    fore = p["fore"]
    s, c = math.sin(math.radians(theta)), math.cos(math.radians(theta))
    if c > 0:
        fore = min(fore, (GROUND - 2 - F[1] - along[0] * s) / (along[1] * c))
    v = rot((along[0], along[1] * fore), theta)
    cane_img = place(rig.cane, grip, F, theta, 1.0, fore)
    tip = (F[0] + v[0], F[1] + v[1])
    tip_dir = (v[0] / math.hypot(*v), v[1] / math.hypot(*v))

    root = body_xf(ARM_ROOT if p.get("reach") else SHOULDER, p)
    fist_img, wrist = grip_fist(rig.fist, F, theta, p.get("elbow") or root)
    near = arm(SLEEVE_UP, SLEEVE_LO, rig.sleeve, root, p.get("elbow"), wrist)

    far, far_fist = [], None
    if p.get("two"):
        g = p["gap"] * fore
        F2 = (F[0] + tip_dir[0] * g, F[1] + tip_dir[1] * g)
        far_root = body_xf(FAR_SHOULDER, p)
        far_fist, w2 = grip_fist(FAR_FIST, F2, theta, p.get("belbow") or far_root)
        far = arm(FAR_UP, FAR_LO, FAR_SLEEVE, far_root, p.get("belbow"), w2)

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
    behind = p["behind"]
    for layer in [fx_back, cane_img if behind else None, *far, far_fist if behind else None, legs,
                  *(near if p.get("reach") else []), upper, fx_mid,
                  *([] if p.get("reach") else near), cap,
                  None if behind else cane_img, None if behind else far_fist, fist_img]:
        if layer is not None:
            frame.alpha_composite(layer)
    return frame, dict(tip=[round(tip[0]), round(tip[1])], fist=list(F))


def main():
    fx_dir, out = sys.argv[1:3]
    preview = sys.argv[3] if len(sys.argv) > 3 else None
    fx_back, fx_mid, fx_top = (rig.fx_strip(fx_dir, "crack_fx_" + n) for n in ("back", "mid", "top"))
    frames, info = [], []
    for i, p in enumerate(POSES):
        f, meta = render(p, rig.cell(fx_back, i), rig.cell(fx_mid, i))
        top = rig.cell(fx_top, i)
        if top is not None:
            f.alpha_composite(top)
        frames.append(f)
        info.append(meta)
    rig.write_outputs("crack", frames, [p["ms"] for p in POSES], out, preview, sys.argv[4] if len(sys.argv) > 4 else None)
    print(json.dumps({"ms": [p["ms"] for p in POSES], "frames": info}))


if __name__ == "__main__":
    main()
