// Kaaji Baje cane sweep: motion FX (smear, impact glint, dust) for assets/kaji_baje/sweep.png.
//
// The body, arm, fist and cane in sweep.png are real pixels from idle.png frame 0, cut into parts
// by sweep_parts/extract.py and posed by sweep_parts/rig.py (full rebuild steps are in rig.py).
// This file paints only the effects; rig.py composites the three layers below. Build:
//   node <pxl>/bin/pxl.js build sweep.px.js --out sweep_parts/fx
//
// CANE lists, per frame, the fist centre and the cane tip that rig.py prints for its POSES; keep
// them in sync when a pose changes.
const W = 256, H = 256, FRAMES = 7

const CANE = [
  { fist: [152, 136], tip: [83, 219] },   // 0 wind-up: tip swings back past the legs
  { fist: [142, 110], tip: [43, 32] },    // 1 cocked over the shoulder
  { fist: [180, 102], tip: [223, 41] },   // 2 whip over the top
  { fist: [200, 140], tip: [251, 215] },  // 3 strike: knee-high, in front
  { fist: [190, 168], tip: [179, 246] },  // 4 follow-through: tip drags into the ground
  { fist: [174, 158], tip: [183, 246] },  // 5 settle
  { fist: [164, 152], tip: [167, 246] },  // 6 back to idle
]

const SHOULDER_STRIKE = [161, 135]   // the strike smear fans out from the shoulder, not the fist

// HUD cream-gold: light rim, #ffe39a body, deeper gold where the smear thins out
pal({ W: "#fffbea", y: "#ffe39a", u: "#efe3c6", U: "#c8b48e" })

const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const keep = (x, y, density) => density * 16 > BAYER[(y & 3) * 4 + (x & 3)]
const lerp = (a, b, t) => a + (b - a) * t

// Crescent smear left by the outer part of the cane between frames `a` and `b`, swinging
// clockwise around `pivot` (default: the midpoint of the two fists). `t` runs 0 (old cane) -> 1 (new cane);
// the crescent is a thin sliver at the old end and widens toward the new cane. Its outer edge
// eases in before the cell border instead of being cut by it.
function crescent(c, a, b, { inner = 0.35, upto = 0.94, minT = 0, maxT = 1, fade = 1, pivot } = {}) {
  const [px, py] = pivot || [(a.fist[0] + b.fist[0]) / 2, (a.fist[1] + b.fist[1]) / 2]
  const polar = (p) => [Math.atan2(p[1] - py, p[0] - px), Math.hypot(p[0] - px, p[1] - py)]
  const [a0, r0] = polar(a.tip)
  let [a1, r1] = polar(b.tip)
  while (a1 < a0) a1 += Math.PI * 2
  const border = (an) => {
    const dx = Math.cos(an), dy = Math.sin(an)
    const tx = dx > 0 ? (251 - px) / dx : dx < 0 ? (4 - px) / dx : 1e9
    const ty = dy > 0 ? (247 - py) / dy : dy < 0 ? (4 - py) / dy : 1e9
    return Math.min(tx, ty)
  }
  for (let y = 0; y < H; y++)
    for (let x = 0; x < W; x++) {
      let an = Math.atan2(y - py, x - px)
      while (an < a0) an += Math.PI * 2
      const t = (an - a0) / (a1 - a0)
      if (t < minT || t > Math.min(maxT, upto)) continue
      const R0 = lerp(r0, r1, t), B = border(an)
      const R = (R0 * B) / Math.pow(Math.pow(R0, 4) + Math.pow(B, 4), 0.25)
      const width = 1 - (1 - inner) * Math.pow(t / upto, 0.8)
      const r = Math.hypot(x - px, y - py) / R
      if (r > 1 || r < width) continue
      const across = (r - width) / (1 - width)          // 0 inner edge .. 1 outer rim
      const k = Math.pow(t / upto, 1.2) * fade
      const alpha = Math.min(1, k * (0.35 + 0.75 * across))
      if (alpha < 0.12) continue
      const step = alpha > 0.8 ? "ee" : alpha > 0.55 ? "b8" : alpha > 0.32 ? "80" : "48"
      const tone = across > 0.82 ? "#fffbea" : across > 0.4 ? "#ffe39a" : "#f4c766"
      c.px(x, y, tone + step)
    }
}

function glint(c, cx, cy, size) {
  for (let i = -size; i <= size; i++) {
    const k = Math.abs(i) <= size / 3 ? "W" : "y"
    c.px(cx + i, cy, k)
    c.px(cx, cy + i, k)
  }
  const diag = Math.round(size / 2)
  for (let i = 1; i <= diag; i++) for (const [sx, sy] of [[1, 1], [1, -1], [-1, 1], [-1, -1]]) c.px(cx + sx * i, cy + sy * i, i === 1 ? "W" : "y")
  c.rect(cx - 1, cy - 1, 3, 3, "W")
}

// Soft dust cloud: dense cream core, thinning to a warm grey rim.
function puff(c, cx, cy, rx, ry, strength) {
  for (let y = -ry; y <= ry; y++)
    for (let x = -rx; x <= rx; x++) {
      const d = Math.hypot(x / rx, y / ry)
      if (d > 1) continue
      const a = strength * (1 - d * d)
      if (a < 0.15) continue
      const step = a > 0.6 ? "c8" : a > 0.4 ? "96" : a > 0.25 ? "64" : "38"
      c.px(cx + x, cy + y, (y > ry / 3 ? "#c8b48e" : "#efe3c6") + step)
    }
}

// Three layers, composited by rig.py: `back` behind the character, `mid` over the body but under
// the arm, fist and cane (a smear never hides the stick), `top` over everything.
const layers = { w: W, h: H, frames: FRAMES, fps: 20, loop: false }

anim("sweep_fx_back", layers, (c) => {
  if (c.frame === 2) crescent(c, CANE[1], CANE[2], { maxT: 0.55 })   // arcs over his head
})

anim("sweep_fx_mid", layers, (c) => {
  if (c.frame === 2) crescent(c, CANE[1], CANE[2], { minT: 0.55 })
  if (c.frame === 3) crescent(c, CANE[2], CANE[3], { pivot: SHOULDER_STRIKE, inner: 0.42 })
  if (c.frame === 4) crescent(c, CANE[3], CANE[4], { inner: 0.86, fade: 0.55, pivot: CANE[4].fist })
})

anim("sweep_fx_top", layers, (c) => {
  const tip = CANE[c.frame].tip
  if (c.frame === 3) glint(c, tip[0] - 8, tip[1] - 7, 9)
  if (c.frame === 4) {
    puff(c, tip[0] - 10, 243, 9, 4, 0.9)
    puff(c, tip[0] + 9, 244, 8, 3, 0.8)
    puff(c, tip[0] - 1, 239, 6, 4, 0.7)
  }
  if (c.frame === 5) {
    puff(c, tip[0] - 18, 240, 10, 5, 0.45)
    puff(c, tip[0] + 15, 241, 9, 4, 0.4)
  }
})
