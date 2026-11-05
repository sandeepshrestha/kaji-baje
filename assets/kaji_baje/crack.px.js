// Kaaji Baje overhead crack: motion FX (smears, impact spark, ground crack, chips, dust) for
// assets/kaji_baje/crack.png.
//
// Body, arms, fists and cane are real idle.png frame-0 pixels: sweep_parts/extract.py cuts them,
// sweep_parts/crack_rig.py poses them (full rebuild steps are in crack_rig.py). This file paints only
// the effects; crack_rig.py composites the three layers below. Build:
//   node <pxl>/bin/pxl.js build crack.px.js --out sweep_parts/fx
//
// CANE lists, per frame, the near fist and the cane tip that crack_rig.py prints for its POSES; keep
// them in sync when a pose changes.
const W = 256, H = 256, FRAMES = 9

const CANE = [
  { fist: [162, 124], tip: [82, 219] },   // 0 lift
  { fist: [180, 98], tip: [65, 154] },    // 1 rising
  { fist: [162, 56], tip: [32, 60] },     // 2 peak: cocked behind the head
  { fist: [194, 72], tip: [250, 48] },    // 3 whip over the top
  { fist: [198, 98], tip: [240, 167] },   // 4 strike: coming down in front
  { fist: [198, 118], tip: [182, 246] },  // 5 impact
  { fist: [196, 110], tip: [185, 233] },  // 6 rebound
  { fist: [174, 150], tip: [174, 246] },  // 7 recover
  { fist: [162, 151], tip: [157, 246] },  // 8 settle (idle)
]

const STRIKE_PIVOT = [170, 110]   // the downstroke fans out from the shoulders, not the fists
const HIT = CANE[5].tip

// HUD cream-gold like the sweep, plus the dust creams
pal({ W: "#fffbea", y: "#ffe39a", u: "#efe3c6", U: "#c8b48e" })

const lerp = (a, b, t) => a + (b - a) * t

// Crescent smear left by the outer part of the cane between frames `a` and `b`, swinging clockwise
// around `pivot` (default: midpoint of the two fists). Same shape and tones as the sweep's.
function crescent(c, a, b, { inner = 0.35, upto = 0.94, minT = 0, maxT = 1, fade = 1, pivot } = {}) {
  const [px, py] = pivot || [(a.fist[0] + b.fist[0]) / 2, (a.fist[1] + b.fist[1]) / 2]
  const polar = (p) => [Math.atan2(p[1] - py, p[0] - px), Math.hypot(p[0] - px, p[1] - py)]
  const [a0, r0] = polar(a.tip)
  let [a1, r1] = polar(b.tip)
  while (a1 < a0) a1 += Math.PI * 2
  const border = (an) => {
    const dx = Math.cos(an), dy = Math.sin(an)
    const tx = dx > 0 ? (251 - px) / dx : dx < 0 ? (4 - px) / dx : 1e9
    const ty = dy > 0 ? (245 - py) / dy : dy < 0 ? (4 - py) / dy : 1e9
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
      const across = (r - width) / (1 - width)
      const k = Math.pow(t / upto, 1.2) * fade
      const alpha = Math.min(1, k * (0.35 + 0.75 * across))
      if (alpha < 0.12) continue
      const step = alpha > 0.8 ? "ee" : alpha > 0.55 ? "b8" : alpha > 0.32 ? "80" : "48"
      const tone = across > 0.82 ? "#fffbea" : across > 0.4 ? "#ffe39a" : "#f4c766"
      c.px(x, y, tone + step)
    }
}

// Four-point spark, smaller and flatter than the sweep's glint: it sits on the ground.
function spark(c, cx, cy, size) {
  for (let i = -size; i <= size; i++) c.px(cx + i, cy, Math.abs(i) <= size / 3 ? "W" : "y")
  for (let i = -Math.round(size * 0.7); i <= 0; i++) c.px(cx, cy + i, i >= -2 ? "W" : "y")
  for (let i = 1; i <= Math.round(size / 2); i++) {
    c.px(cx - i, cy - i, i === 1 ? "W" : "y")
    c.px(cx + i, cy - i, i === 1 ? "W" : "y")
  }
  c.rect(cx - 1, cy - 1, 3, 2, "W")
}

// Short ground crack either side of the tip: a jagged dark seam on the ground line, pale lip above,
// two hairline branches. `alpha` fades it out.
const SEAM = [0, 0, -1, -1, 0, 0, 1, 0, -1, -2, -1, 0, 0, 0, 0, 0, 0, -1, 0, 1, 1, 0, -1, -1, 0, 0, 0, 1, 0, 0, -1]
function crack(c, [tx], alpha = "ff") {
  const x0 = tx - 15
  SEAM.forEach((d, i) => {
    const x = x0 + i, y = 246 + d
    const edge = i < 3 || i > SEAM.length - 4
    const a = edge ? "80" : alpha
    c.px(x, y, "#3b2a22" + a)
    if (Math.abs(i - 15) < 7) c.px(x, y + 1, "#3b2a22" + a)   // gapes wider where the cane hit
    if (!edge && i % 3 !== 1) c.px(x, y - 1, "#efe3c6" + "a0")
  })
  for (const [bx, dir, n] of [[tx - 6, -1, 3], [tx + 7, 1, 2]])
    for (let k = 1; k <= n; k++) c.px(bx + dir * k, 246 - k, "#3b2a22" + alpha)
}

function chip(c, x, y) {
  c.rect(x, y, 2, 1, "u")
  c.px(x, y + 1, "U")
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

// Three layers, composited by crack_rig.py: `back` behind the character (the crack sits under the
// ferrule), `mid` over the body but under the arms, fists and cane, `top` over everything.
const layers = { w: W, h: H, frames: FRAMES, fps: 20, loop: false }

anim("crack_fx_back", layers, (c) => {
  if (c.frame === 3) crescent(c, CANE[2], CANE[3], { maxT: 0.5 })   // over and behind his head
  if (c.frame === 5 || c.frame === 6) crack(c, HIT)
  if (c.frame === 7) crack(c, HIT, "80")
})

anim("crack_fx_mid", layers, (c) => {
  if (c.frame === 3) crescent(c, CANE[2], CANE[3], { minT: 0.5 })
  if (c.frame === 4) crescent(c, CANE[3], CANE[4], { pivot: STRIKE_PIVOT, inner: 0.4 })
  if (c.frame === 5) crescent(c, CANE[4], CANE[5], { inner: 0.86, fade: 0.55, pivot: CANE[5].fist })
})

anim("crack_fx_top", layers, (c) => {
  const [tx] = HIT
  if (c.frame === 5) {
    spark(c, tx, 243, 9)
    puff(c, tx - 9, 243, 8, 3, 0.85)
    puff(c, tx + 10, 244, 7, 3, 0.75)
    chip(c, tx - 9, 236); chip(c, tx + 10, 234); chip(c, tx - 4, 231); chip(c, tx + 5, 238)
  }
  if (c.frame === 6) {
    puff(c, tx - 15, 241, 10, 4, 0.6)
    puff(c, tx + 14, 242, 9, 4, 0.55)
    puff(c, tx, 238, 6, 4, 0.45)
    chip(c, tx - 18, 230); chip(c, tx + 21, 227); chip(c, tx - 11, 224); chip(c, tx + 13, 233)
  }
  if (c.frame === 7) {
    puff(c, tx - 22, 240, 10, 4, 0.35)
    puff(c, tx + 20, 241, 9, 4, 0.3)
    chip(c, tx - 26, 245); chip(c, tx + 28, 245)
  }
})
