"""Synthesise the test game's sound effects with NumPy.

python3 tools/gen_sfx.py  ->  assets/sfx/*.wav
Loops carry a WAV 'smpl' chunk so Godot loops them automatically.
"""
import os
import struct

import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = np.random.default_rng(3)


def t(d):
    return np.arange(int(d * SR)) / SR


def env(d, decay, attack=0.002):
    x = t(d)
    return np.exp(-x / decay) * np.clip(x / attack, 0, 1)


def band(x, lo=None, hi=None):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1 / (1 + (lo / np.maximum(f, 1)) ** 4)
    if hi:
        g *= 1 / (1 + (f / hi) ** 4)
    return np.fft.irfft(X * g, len(x))


def norm(x, peak=0.8):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def write(name, x, loop=False):
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    body = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, 0, len(x) - 1, 0, 0)
        body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(body)) + b"WAVE" + body)


def step(i, hard=False):
    """Leather sandal on stone: a soft slap plus a low heel thump."""
    r = np.random.default_rng(10 + i + (20 if hard else 0))
    d = 0.22
    slap = band(r.uniform(-1, 1, int(d * SR)), 700 + i * 120, 5000) * env(d, 0.018 if hard else 0.025)
    heel = np.sin(2 * np.pi * (90 + i * 8) * t(d) * (1 - 0.3 * t(d))) * env(d, 0.03)
    grit = band(r.uniform(-1, 1, int(d * SR)), 3000, 9000) * env(d, 0.008) * 0.3
    return norm(slap + heel * (0.9 if hard else 0.6) + grit, 0.75 if hard else 0.55)


def cane(i):
    """Wooden cane tip tapping stone: short knock with a hollow resonance."""
    d = 0.25
    f0 = 820 + i * 60
    knock = (np.sin(2 * np.pi * f0 * t(d)) + 0.5 * np.sin(2 * np.pi * f0 * 2.7 * t(d))) * env(d, 0.03)
    click = band(rng.uniform(-1, 1, int(d * SR)), 2000, 8000) * env(d, 0.004)
    return norm(knock * 0.7 + click * 0.6, 0.45)


def whoosh():
    d = 0.4
    n = band(rng.uniform(-1, 1, int(d * SR)), 400, 3500)
    shape = np.sin(np.pi * np.clip(t(d) / d, 0, 1)) ** 2
    return norm(n * shape, 0.5)


def thud():
    d = 0.3
    x = np.sin(2 * np.pi * 70 * t(d) * (1 - 0.4 * t(d))) * env(d, 0.06) + band(rng.uniform(-1, 1, int(d * SR)), 100, 1200) * env(d, 0.02)
    return norm(x, 0.6)


# Sa = C. A mangal-dhun phrase uses the full bilawal scale, not a pentatonic pluck.
NOTES = {
    "C3": 130.81, "G3": 196.00,
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23,
    "G4": 392.00, "A4": 440.00, "B4": 493.88, "C5": 523.25,
}


def _pluck(freq, n, decay=0.995, seed=1):
    """Karplus-Strong string. Sounds like a small kalimba."""
    r = np.random.default_rng(seed)
    delay = max(2, int(round(SR / freq)))
    buf = r.uniform(-1, 1, delay)
    out = np.empty(n)
    idx = 0
    for i in range(n):
        out[i] = buf[idx]
        buf[idx] = 0.5 * (buf[idx] + buf[(idx + 1) % delay]) * decay
        idx = (idx + 1) % delay
    attack = min(48, n)
    out[:attack] *= np.linspace(0, 1, attack)
    return out


def _bansuri(freq, n, grace=None, seed=1):
    """Breathy flute: a short meend into the note, then a slow vibrato."""
    x = np.arange(n) / SR
    vib = 1.0 + 0.011 * np.sin(2 * np.pi * 5.1 * x) * np.clip(x / 0.16, 0, 1)
    f = np.full(n, freq) * vib
    if grace:
        g = min(int(0.07 * SR), max(2, n // 3))
        f[:g] = np.linspace(grace, freq, g)
    phase = 2 * np.pi * np.cumsum(f) / SR
    breath = band(np.random.default_rng(seed).uniform(-1, 1, n), 700, 4200)
    tone = np.sin(phase) + 0.2 * np.sin(2 * phase) + 0.05 * np.sin(3 * phase) + 0.07 * breath
    att = np.clip(x / 0.035, 0, 1)
    rel = np.clip((n / SR - x) / 0.14, 0, 1)
    return tone * att * rel


def _madal(low, n, seed):
    """Madal hit. The low head is the deep dha; the high head is the tin."""
    r = np.random.default_rng(seed)
    x = np.arange(n) / SR
    if low:
        f = 96 * (1 - 0.4 * np.clip(x / 0.07, 0, 1))
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-x / 0.11)
        slap = band(r.uniform(-1, 1, n), 160, 800) * np.exp(-x / 0.018)
        return body * 0.9 + slap * 0.5
    f = 286 * (1 - 0.25 * np.clip(x / 0.035, 0, 1))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-x / 0.04)
    tick = band(r.uniform(-1, 1, n), 900, 4500) * np.exp(-x / 0.007)
    return body * 0.45 + tick * 0.4


def tune():
    """Mangal-dhun loop. Bansuri over a madal in a swaying six, with a Sa-Pa drone.

    The line is original: it opens on Pa, climbs to the upper Sa, and resolves
    back to Sa the way an auspicious dhun does. Eighth = 0.30 s, eight bars of six.
    """
    eighth = 0.30
    steps = 48
    n = int(steps * eighth * SR)
    out = np.zeros(n)
    k_sa = int(round(NOTES["C3"] * n / SR))
    k_pa = int(round(NOTES["G3"] * n / SR))
    i = np.arange(n)
    drone = 0.16 * np.sin(2 * np.pi * k_sa * i / n) + 0.10 * np.sin(2 * np.pi * k_pa * i / n)
    out += drone
    # start eighth, length in eighths, note, grace
    phrase = [
        (0, 1, "G4", "F4"), (1, 1, "G4", None), (2, 1, "A4", "G4"),
        (3, 1, "B4", "A4"), (4, 2, "C5", "B4"),
        (6, 1, "B4", None), (7, 1, "A4", "B4"), (8, 1, "G4", None),
        (9, 1, "F4", "G4"), (10, 1, "E4", None), (11, 1, "D4", "E4"),
        (12, 1, "E4", "D4"), (13, 1, "F4", None), (14, 1, "G4", "F4"),
        (15, 2, "A4", "G4"), (17, 1, "G4", None), (18, 1, "E4", "F4"),
        (19, 1, "D4", None), (20, 1, "E4", "D4"), (21, 1, "D4", "E4"),
        (22, 2, "C4", "D4"),
        (24, 1, "C4", None), (25, 1, "D4", "C4"), (26, 1, "E4", None),
        (27, 1, "G4", "E4"), (28, 2, "A4", "G4"), (30, 1, "G4", None),
        (31, 1, "E4", "G4"), (32, 1, "D4", None), (33, 1, "C4", "D4"),
        (34, 1, "D4", "C4"), (35, 1, "E4", None), (36, 2, "G4", "E4"),
        (38, 1, "A4", "G4"), (39, 1, "G4", None), (40, 1, "E4", "G4"),
        (41, 1, "D4", None), (42, 1, "C4", "D4"), (43, 1, "D4", "E4"),
        (44, 1, "E4", "D4"), (45, 1, "D4", None), (46, 2, "C4", "D4"),
    ]
    for i_note, (start_e, length, name, grace) in enumerate(phrase):
        start = int(start_e * eighth * SR)
        dur = int((length * eighth + 0.16) * SR)
        end = min(n, start + dur)
        grace_f = NOTES[grace] if grace else None
        tone = _bansuri(NOTES[name], end - start, grace_f, seed=40 + i_note)
        out[start:end] += tone * 0.72
    # Madal theka, six eighths to the bar: dha, tin, tin, dha, tin, tin.
    hit_n = int(0.28 * SR)
    for e in range(steps):
        if e >= steps - 1:
            continue
        low = e % 6 in (0, 3)
        start = int(e * eighth * SR)
        end = min(n, start + hit_n)
        hit = _madal(low, end - start, seed=80 + e)
        out[start:end] += hit * (0.42 if low else 0.22)
    fade = int(0.012 * SR)
    out[:fade] *= np.linspace(0, 1, fade)
    out[-fade:] *= np.linspace(1, 0, fade)
    return norm(out, 0.5)


def whistle():
    """A short bansuri turn, Pa up to Sa, instead of the old bird call."""
    out = np.zeros(int(0.9 * SR))
    for start, dur, f0, f1 in ((0.04, 0.34, 392.0, 523.25), (0.42, 0.40, 523.25, 392.0)):
        x = t(dur)
        slide = 0.55 * (1 - np.exp(-x / 0.08))
        f = f0 + (f1 - f0) * slide
        vib = 1.0 + 0.01 * np.sin(2 * np.pi * 5.0 * x) * np.clip(x / 0.12, 0, 1)
        phase = 2 * np.pi * np.cumsum(f * vib) / SR
        e = np.sin(np.pi * np.clip(x / dur, 0, 1)) ** 0.8
        breath = band(np.random.default_rng(7).uniform(-1, 1, len(x)), 700, 4000)
        s = int(start * SR)
        out[s:s + len(x)] += (np.sin(phase) + 0.18 * np.sin(2 * phase) + 0.05 * breath) * e
    return norm(out, 0.4)


def lamp_glow():
    """One soft bell, then silence. Lamps play it staggered so they twinkle."""
    out = np.zeros(int(2.4 * SR))
    x = t(0.55)
    f = 1568.0
    e = np.exp(-x / 0.11) * np.clip(x / 0.004, 0, 1)
    bell = np.sin(2 * np.pi * f * x) + 0.45 * np.sin(2 * np.pi * f * 2.0 * x) + 0.18 * np.sin(2 * np.pi * f * 2.76 * x)
    out[: len(x)] = bell * e
    return norm(out, 0.4)


def jump():
    """Push-off: a short cloth swish over a soft sandal scuff."""
    d = 0.22
    swish = band(rng.uniform(-1, 1, int(d * SR)), 900, 5000) * np.sin(np.pi * np.clip(t(d) / d, 0, 1)) ** 2
    scuff = band(rng.uniform(-1, 1, int(d * SR)), 300, 2500) * env(d, 0.02)
    return norm(swish * 0.7 + scuff, 0.45)


def double_jump():
    """Airy upward sweep with a soft rising tone."""
    d = 0.32
    x = t(d)
    f = 420 + 900 * (x / d) ** 0.7
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * x / d) ** 1.5
    air = band(rng.uniform(-1, 1, len(x)), 1500, 7000) * np.sin(np.pi * x / d) ** 2
    return norm(tone * 0.35 + air * 0.6, 0.45)


def land():
    """Both sandals hitting stone at once: low thump plus a slap."""
    d = 0.3
    thump = np.sin(2 * np.pi * 85 * t(d) * (1 - 0.35 * t(d))) * env(d, 0.05)
    slap = band(rng.uniform(-1, 1, int(d * SR)), 600, 4500) * env(d, 0.02)
    return norm(thump + slap * 0.8, 0.65)


def coin():
    """Two-note bright chime (B5 then E6) with a metallic shimmer."""
    out = np.zeros(int(0.5 * SR))
    for start, f in ((0.0, 987.8), (0.07, 1318.5)):
        s = int(start * SR)
        x = np.arange(len(out) - s) / SR
        e = np.exp(-x / 0.12) * np.clip(x / 0.002, 0, 1)
        out[s:] += (np.sin(2 * np.pi * f * x) + 0.35 * np.sin(2 * np.pi * f * 2.01 * x) + 0.15 * np.sin(2 * np.pi * f * 3.02 * x)) * e
    return norm(out, 0.5)


def stomp_pop():
    """Cartoon squash: a short falling blip."""
    d = 0.2
    x = t(d)
    f = 740 - 520 * (x / d)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-x / 0.045)
    return norm(tone, 0.55)


def hit_bonk():
    """The cube bumping into the hero."""
    d = 0.16
    x = t(d)
    knock = np.sin(2 * np.pi * 196 * x * (1 - 0.45 * x)) * np.exp(-x / 0.035)
    tick = np.sin(2 * np.pi * 720 * x) * np.exp(-x / 0.01)
    return norm(knock + tick * 0.35, 0.5)


def main():
    os.makedirs(OUT, exist_ok=True)
    for i in range(4):
        write(f"step_{i + 1}", step(i))
        write(f"step_run_{i + 1}", step(i, True))
    for i in range(3):
        write(f"cane_{i + 1}", cane(i))
    write("whoosh", whoosh())
    write("thud", thud())
    write("tune", tune(), loop=True)
    write("whistle", whistle())
    write("lamp_glow", lamp_glow(), loop=True)
    write("jump", jump())
    write("double_jump", double_jump())
    write("land", land())
    write("coin", coin())
    write("stomp", stomp_pop())
    write("hit", hit_bonk())
    print("sfx written to assets/sfx")


if __name__ == "__main__":
    main()
