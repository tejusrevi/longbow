#!/usr/bin/env python3
"""Synthesises the game's sound effects (spec A15) into Resources/Sounds/*.wav.

Pure standard library (math, random, wave) so it runs anywhere. Every sound is
built from simple oscillators, filtered noise and envelopes; the style is
deliberately dry and minimal to match the black-and-white look.
Run:  python3 Tools/gen_sounds.py
"""
import math
import os
import random
import struct
import wave

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "Sounds")
TAU = 2 * math.pi


def n(sec):
    return int(sec * SR)


def env_ad(i, total, attack=0.005, decay_pow=2.0):
    t = i / SR
    a = min(1.0, t / attack) if attack > 0 else 1.0
    d = (1 - i / total) ** decay_pow
    return a * d


def lowpass(samples, cutoff):
    rc = 1 / (TAU * cutoff)
    dt = 1 / SR
    alpha = dt / (rc + dt)
    out, y = [], 0.0
    for s in samples:
        y += alpha * (s - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    rc = 1 / (TAU * cutoff)
    dt = 1 / SR
    alpha = rc / (rc + dt)
    out, y, prev = [], 0.0, 0.0
    for s in samples:
        y = alpha * (y + s - prev)
        prev = s
        out.append(y)
    return out


def bandpass(samples, lo, hi):
    return lowpass(highpass(samples, lo), hi)


def noise(count, seed):
    r = random.Random(seed)
    return [r.uniform(-1, 1) for _ in range(count)]


def mix(*tracks):
    length = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(length)]


def gain(samples, g):
    return [s * g for s in samples]


def normalise(samples, peak=0.85):
    m = max(1e-9, max(abs(s) for s in samples))
    return [s * peak / m for s in samples]


def fade_out(samples, sec=0.01):
    k = n(sec)
    out = list(samples)
    for i in range(min(k, len(out))):
        out[-1 - i] *= i / k
    return out


def write(name, samples, peak=0.85):
    samples = fade_out(normalise(samples, peak))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))
    print("wrote", os.path.relpath(path, ROOT))


def tone(freq_fn, sec, wave_fn=math.sin, env=None):
    total = n(sec)
    phase = 0.0
    out = []
    for i in range(total):
        f = freq_fn(i / SR) if callable(freq_fn) else freq_fn
        phase += TAU * f / SR
        v = wave_fn(phase)
        out.append(v * (env(i, total) if env else 1))
    return out


def tri(p):
    return 2 / math.pi * math.asin(math.sin(p))


def saw(p):
    x = (p / TAU) % 1.0
    return 2 * x - 1


# --- Sounds -----------------------------------------------------------------

def ratchet(level):
    """One click of the bow being cranked back; pitch climbs with draw power."""
    f = 900 + 1400 * (level - 1) / 5
    body = tone(f, 0.03, math.sin, lambda i, T: 0.7 * env_ad(i, T, 0.0005, 5))
    knock = lowpass(noise(n(0.015), 100 + level), 3000)
    knock = [x * env_ad(i, len(knock), 0.0003, 4) * 0.5 for i, x in enumerate(knock)]
    return mix(body, knock)


def twang(f0=392, sec=0.35, seed=52):
    """A plinky cartoon bowstring: bright triangle string with a quick
    downward pitch settle, a hint of wobble, and a short snap on the attack."""
    def f(t, mult=1):
        return mult * f0 * (1 + 0.18 * math.exp(-t * 30)) * (1 + 0.006 * math.sin(t * TAU * 14))
    string = tone(lambda t: f(t), sec, tri, lambda i, T: env_ad(i, T, 0.001, 3.5))
    over = tone(lambda t: f(t, 2), sec * 0.7, math.sin, lambda i, T: 0.55 * env_ad(i, T, 0.001, 5))
    snap = bandpass(noise(n(0.015), seed), 2000, 8000)
    snap = [c * env_ad(i, len(snap), 0.0002, 3) * 0.7 for i, c in enumerate(snap)]
    return mix(string, over, snap)


def whoosh(sec=0.35, seed=4, hi=5200, lo=1400):
    """A short, clean air-cut: fast in, falling pitch, quick fade."""
    total = n(sec)
    raw = noise(total, seed)
    out, y1, y2 = [], 0.0, 0.0
    for i, s in enumerate(raw):
        t = i / total
        cutoff = hi * (lo / hi) ** t
        alpha = (1 / SR) / (1 / (TAU * cutoff) + 1 / SR)
        y1 += alpha * (s - y1)
        y2 += alpha * (y1 - y2)
        amp = min(1, t / 0.08) * (1 - t) ** 2.2
        out.append(y2 * amp)
    return highpass(out, 600)


def wind_whoosh(sec=0.9, seed=4, top=2600):
    total = n(sec)
    raw = noise(total, seed)
    out = []
    y = 0.0
    for i, s in enumerate(raw):
        t = i / total
        cutoff = 400 + top * math.sin(math.pi * t)
        alpha = (1 / SR) / (1 / (TAU * cutoff) + 1 / SR)
        y += alpha * (s - y)
        out.append(y * math.sin(math.pi * t) ** 1.5)
    return highpass(out, 150)


def thunk(wood, f0=None, seed=None, grit=1.0):
    total = n(0.35)
    f0 = f0 or (210 if wood else 95)
    body = tone(lambda t: f0 * (1 + 1.2 * math.exp(-t * 60)), 0.35, math.sin, lambda i, T: env_ad(i, T, 0.001, 5 if wood else 3))
    hit = noise(n(0.06 * grit), seed or (5 if wood else 6))
    hit = lowpass(hit, 2500 if wood else 900 * grit)
    hit = [h * env_ad(i, len(hit), 0.0005, 3) for i, h in enumerate(hit)]
    knock = tone(f0 * 3.1, 0.12, math.sin, lambda i, T: 0.3 * env_ad(i, T, 0.0005, 6)) if wood else []
    return mix(body, gain(hit, 0.8), knock)


def burst(sec, seed, lo, hi, amp, pow_=3):
    s = bandpass(noise(n(sec), seed), lo, hi)
    return [c * env_ad(i, len(s), 0.0003, pow_) * amp for i, c in enumerate(s)]


def pitch_drop(f_hi, f_lo, rate, sec, amp, pow_=3, wave=math.sin):
    return tone(lambda t: f_lo + (f_hi - f_lo) * math.exp(-t * rate), sec, wave,
                lambda i, T: amp * env_ad(i, T, 0.001, pow_))


def hollow(freqs, sec, amp, pow_=6):
    """Resonant partials of a hollow knock (wood block, log, skull)."""
    return mix(*[tone(f, sec, math.sin, lambda i, T, k=k: amp / (k + 1) * env_ad(i, T, 0.001, pow_ + k))
                 for k, f in enumerate(freqs)])


def thup(f_hi=150, f_lo=55, seed=1):
    """Arrow into the ground: a soft falling thud with a puff of dirt."""
    return mix(pitch_drop(f_hi, f_lo, 40, 0.3, 1.0, 3), lowpass(burst(0.06, seed, 80, 900, 0.7), 900))


def boing(f0=330, wobble_hz=9):
    """Body hit: a cartoon spring boing."""
    return tone(lambda t: f0 * (1 + 0.6 * math.exp(-t * 5) * math.sin(t * TAU * wobble_hz)) * (1 + 0.5 * math.exp(-t * 12)),
                0.6, tri, lambda i, T: 0.9 * env_ad(i, T, 0.001, 2.2))


def grunt(f0=150, sec=0.32, f1=(500, 800), f2=(950, 1300), fall=0.25):
    """A cartoon grunt: glottal pulse train through two vowel formants."""
    total = n(sec)
    out, phase = [], 0.0
    for i in range(total):
        t = i / SR
        f = f0 * (1 - fall * t / sec)
        phase += TAU * f / SR
        pulse = (phase / TAU) % 1.0
        out.append((1 - pulse) ** 6 * 2 - 0.3)
    a = bandpass(out, f1[0], f1[1])
    b = bandpass(out, f2[0], f2[1])
    v = mix(a, gain(b, 0.6))
    return [s * env_ad(i, total, 0.02, 1.2) for i, s in enumerate(v)]


def bonk():
    return tone(lambda t: 520 * math.exp(-t * 5) + 180, 0.3, tri, lambda i, T: env_ad(i, T, 0.001, 3))


def clang():
    """Headshot: a hollow bonk with a little ring on top."""
    return mix(pitch_drop(700, 380, 30, 0.2, 0.8, 4, tri), hollow([2100, 3150, 5300], 0.5, 0.35, 3))


def ooh():
    """Crowd-less 'ooh': a soft falling whistle."""
    def f(t):
        return 1200 - 500 * (t / 0.7) ** 0.8
    w = tone(f, 0.7, math.sin, lambda i, T: math.sin(math.pi * i / T) ** 0.7)
    vib = tone(lambda t: f(t) * (1 + 0.01 * math.sin(TAU * 6 * t)), 0.7, math.sin,
               lambda i, T: 0.2 * math.sin(math.pi * i / T))
    breath = bandpass(noise(n(0.7), 9), 1500, 4000)
    breath = [b * 0.06 * math.sin(math.pi * i / len(breath)) for i, b in enumerate(breath)]
    return mix(w, vib, breath)


def toss_spin():
    tick = bandpass(noise(n(0.03), 11), 1500, 6000)
    return [t * env_ad(i, len(tick), 0.0005, 5) for i, t in enumerate(tick)]


def toss_click():
    a = tone(1800, 0.08, math.sin, lambda i, T: env_ad(i, T, 0.0005, 6))
    b = thunk(True)[: n(0.15)]
    return mix(a, gain(b, 0.6))


def notes(seq, sec_per, wave_fn=tri, decay=3):
    out = []
    for f in seq:
        if f == 0:
            out += [0.0] * n(sec_per)
        else:
            out += tone(f, sec_per, wave_fn, lambda i, T: env_ad(i, T, 0.003, decay))
    return out


def jingle_round():
    return notes([523, 659, 784], 0.11) + tone(1047, 0.35, tri, lambda i, T: env_ad(i, T, 0.003, 2))


def jingle_match():
    lead = notes([523, 659, 784, 0, 659, 784], 0.1) + tone(1047, 0.6, tri, lambda i, T: env_ad(i, T, 0.003, 1.5))
    bass = notes([131, 0, 196, 0, 165, 196], 0.1, math.sin) + tone(262, 0.6, math.sin, lambda i, T: env_ad(i, T, 0.003, 1.5))
    return mix(lead, gain(bass, 0.5))


def jingle_lose():
    return notes([392, 370, 349], 0.16) + tone(262, 0.6, tri, lambda i, T: env_ad(i, T, 0.003, 1.5))


def chicken_syllable(sec, f_fn, rasp, seed=77):
    """One chicken 'buk': a raspy, nasal pulse train."""
    r = random.Random(seed)
    total = n(sec)
    out, phase = [], 0.0
    for i in range(total):
        t = i / SR
        f = f_fn(t / sec) * (1 + r.uniform(-rasp, rasp))
        phase += TAU * f / SR
        pulse = (phase / TAU) % 1.0
        out.append((1 - pulse) ** 4 * 2 - 0.5)
    nasal = bandpass(out, 850, 1500)
    bright = bandpass(out, 2200, 3600)
    v = mix(nasal, gain(bright, 0.7))
    grit = bandpass(gain(noise(total, 31), 0.5), 1800, 5000)
    v = mix(v, [g * 0.35 for g in grit])
    return [x * env_ad(i, total, 0.008, 1.6) for i, x in enumerate(v)]


def squawk():
    """A startled chicken: a short 'buk' then a rising, raspy 'BAWK!'."""
    buk = chicken_syllable(0.075, lambda u: 520 + 80 * u, 0.04)
    gap = [0.0] * n(0.05)
    bawk = chicken_syllable(0.34, lambda u: 560 + 360 * math.sin(math.pi * min(1, u * 1.6)) - 160 * u, 0.09)
    return buk + gap + bawk


def cluck(f=480, seed=1):
    """A curious chicken: 'buk-buk?' rising at the end."""
    a = chicken_syllable(0.06, lambda u: f + 40 * u, 0.03, seed)
    b = chicken_syllable(0.09, lambda u: f * 1.08 + 140 * u, 0.04, seed + 1)
    return a + [0.0] * n(0.045) + b


def cackle():
    """A mocking chicken laugh: 'buk buk buk buk BA-GAWK!'"""
    out = []
    for k in range(4):
        out += chicken_syllable(0.055, lambda u, k=k: 500 + 30 * k - 60 * u, 0.05, 30 + k) + [0.0] * n(0.035)
    out += chicken_syllable(0.07, lambda u: 620 + 60 * u, 0.06, 40) + [0.0] * n(0.02)
    out += chicken_syllable(0.3, lambda u: 700 + 300 * math.sin(math.pi * min(1, u * 1.4)) - 200 * u, 0.1, 41)
    return out


def stamp():
    """A paper label slapped onto glass: papery crack and a soft knock."""
    crack = bandpass(noise(n(0.09), 51), 900, 7000)
    crack = [c * env_ad(i, len(crack), 0.0005, 5) for i, c in enumerate(crack)]
    knock = tone(lambda t: 160 * (1 + 0.6 * math.exp(-t * 40)), 0.18, math.sin, lambda i, T: 0.7 * env_ad(i, T, 0.001, 4))
    return mix(crack, knock)


def peck():
    """A beak tapping a camera lens: a hard, glassy tick that rings."""
    tick = bandpass(noise(n(0.012), 52), 2500, 9000)
    tick = [t * env_ad(i, len(tick), 0.0002, 3) for i, t in enumerate(tick)]
    ring = mix(*[tone(f, 0.35, math.sin, lambda i, T, a=a, d=d: a * math.exp(-i / SR * d))
                 for f, a, d in [(3150, 0.5, 14), (4820, 0.3, 18), (6900, 0.2, 24)]])
    return mix(tick, ring)


def scuff():
    """Stumbling feet in grass: three gritty scrapes."""
    out = []
    for k in range(3):
        sec = 0.09 - 0.015 * k
        g = bandpass(noise(n(sec), 60 + k), 600, 3200)
        out += [x * math.sin(math.pi * i / len(g)) ** 0.6 * (1 - 0.2 * k) for i, x in enumerate(g)] + [0.0] * n(0.06)
    return out


def gust():
    """A soft breath of wind."""
    return [x * 0.8 for x in wind_whoosh(sec=1.1, seed=70, top=900)]


def click():
    return click_tone(2200)


def click_tone(f):
    return tone(f, 0.025, math.sin, lambda i, T: env_ad(i, T, 0.0005, 4))





def main():
    for k in range(1, 7):
        write(f"ratchet_{k}", ratchet(k), 0.6)
    write("twang", twang())
    write("twang_2", twang(f0=370, sec=0.37, seed=13))
    write("twang_3", twang(f0=415, sec=0.33, seed=23))
    write("whoosh", whoosh(), 0.45)
    write("whoosh_2", whoosh(sec=0.3, seed=14, hi=6000, lo=1800), 0.45)
    write("thunk_dirt", thup())
    write("thunk_dirt_2", thup(f_hi=135, f_lo=50, seed=16))
    write("thunk_dirt_3", thup(f_hi=165, f_lo=62, seed=26))
    write("thunk_wood", thunk(True))
    write("thwack", boing())
    write("thwack_2", boing(f0=305, wobble_hz=8))
    write("thwack_3", boing(f0=355, wobble_hz=10))
    write("grunt", grunt(), 0.6)  # "hmpf"
    write("grunt_2", grunt(f0=120, sec=0.36, f1=(380, 620), f2=(700, 1000), fall=0.35), 0.6)  # "oof"
    write("grunt_3", grunt(f0=175, sec=0.28, f1=(650, 950), f2=(1150, 1600), fall=0.1), 0.6)  # "ugh"
    write("bonk", bonk(), 0.7)
    write("clang", clang(), 0.7)
    write("ooh", ooh(), 0.55)
    write("toss_spin", toss_spin(), 0.4)
    write("toss_click", toss_click())
    write("jingle_round", jingle_round(), 0.6)
    write("jingle_match", jingle_match(), 0.6)
    write("jingle_lose", jingle_lose(), 0.6)
    write("click", click(), 0.4)
    write("click_2", click_tone(1700), 0.4)
    write("squawk", squawk(), 0.7)
    write("cluck", cluck(), 0.55)
    write("cluck_2", cluck(f=540, seed=5), 0.55)
    write("cluck_3", cluck(f=430, seed=9), 0.55)
    write("cackle", cackle(), 0.65)
    write("stamp", stamp(), 0.7)
    write("peck", peck(), 0.6)
    write("scuff", scuff(), 0.5)
    write("gust", gust(), 0.35)


if __name__ == "__main__":
    main()
