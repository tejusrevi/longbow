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

def creak(level):
    """Short wooden bowstring creak; pitch rises with draw power."""
    base = 140 + level * 45
    total = n(0.11)
    r = random.Random(level)
    out, phase = [], 0.0
    for i in range(total):
        t = i / SR
        # Stick-slip: a buzzy saw with jittered pitch.
        f = base * (1 + 0.04 * math.sin(TAU * 31 * t)) * (1 + r.uniform(-0.02, 0.02))
        phase += TAU * f / SR
        out.append(saw(phase) * env_ad(i, total, 0.004, 1.5))
    out = bandpass(out, 300, 2600)
    grit = bandpass(gain(noise(total, 10 + level), 0.4), 1500, 5000)
    grit = [g * env_ad(i, total, 0.002, 3) for i, g in enumerate(grit)]
    return mix(out, grit)


def twang():
    total = n(0.45)
    a = tone(lambda t: 196 * (1 + 0.3 * math.exp(-t * 40)), 0.45, tri, lambda i, T: env_ad(i, T, 0.001, 4))
    b = tone(lambda t: 392 * (1 + 0.2 * math.exp(-t * 50)), 0.45, math.sin, lambda i, T: 0.4 * env_ad(i, T, 0.001, 6))
    click = bandpass(noise(n(0.03), 3), 800, 6000)
    click = [c * env_ad(i, len(click), 0.0005, 4) * 0.7 for i, c in enumerate(click)]
    return mix(a, b, click)


def whoosh():
    total = n(0.9)
    raw = noise(total, 4)
    out = []
    y = 0.0
    for i, s in enumerate(raw):
        t = i / total
        cutoff = 400 + 2600 * math.sin(math.pi * t)
        alpha = (1 / SR) / (1 / (TAU * cutoff) + 1 / SR)
        y += alpha * (s - y)
        out.append(y * math.sin(math.pi * t) ** 1.5)
    return highpass(out, 150)


def thunk(wood):
    total = n(0.35)
    f0 = 210 if wood else 95
    body = tone(lambda t: f0 * (1 + 1.2 * math.exp(-t * 60)), 0.35, math.sin, lambda i, T: env_ad(i, T, 0.001, 5 if wood else 3))
    hit = noise(n(0.06), 5 if wood else 6)
    hit = lowpass(hit, 2500 if wood else 900)
    hit = [h * env_ad(i, len(hit), 0.0005, 3) for i, h in enumerate(hit)]
    knock = tone(f0 * 3.1, 0.12, math.sin, lambda i, T: 0.3 * env_ad(i, T, 0.0005, 6)) if wood else []
    return mix(body, gain(hit, 0.8), knock)


def thwack():
    total = n(0.25)
    slap = bandpass(noise(total, 7), 500, 3500)
    slap = [s * env_ad(i, total, 0.0005, 6) for i, s in enumerate(slap)]
    thud = tone(lambda t: 120 * (1 + math.exp(-t * 50)), 0.25, math.sin, lambda i, T: env_ad(i, T, 0.001, 4))
    return mix(slap, thud)


def grunt():
    """A cartoon 'hmpf': glottal pulse train through two vowel formants."""
    total = n(0.32)
    out, phase = [], 0.0
    for i in range(total):
        t = i / SR
        f = 150 * (1 - 0.25 * t / 0.32)
        phase += TAU * f / SR
        pulse = (phase / TAU) % 1.0
        out.append((1 - pulse) ** 6 * 2 - 0.3)
    a = bandpass(out, 500, 800)
    b = bandpass(out, 950, 1300)
    v = mix(a, gain(b, 0.6))
    return [s * env_ad(i, total, 0.02, 1.2) for i, s in enumerate(v)]


def bonk():
    return tone(lambda t: 520 * math.exp(-t * 5) + 180, 0.3, tri, lambda i, T: env_ad(i, T, 0.001, 3))


def clang():
    partials = [(523, 1.0, 3), (1290, 0.6, 5), (2210, 0.4, 7), (3130, 0.25, 9), (4400, 0.15, 12)]
    tracks = [tone(f, 0.9, math.sin, lambda i, T, a=a, d=d: a * math.exp(-i / SR * d)) for f, a, d in partials]
    hit = bandpass(noise(n(0.02), 8), 2000, 8000)
    return mix(*tracks, gain(hit, 0.5))


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


def squawk():
    """A startled chicken: a short 'buk' then a rising, raspy 'BAWK!'."""
    r = random.Random(77)

    def syllable(sec, f_fn, rasp):
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

    buk = syllable(0.075, lambda u: 520 + 80 * u, 0.04)
    gap = [0.0] * n(0.05)
    bawk = syllable(0.34, lambda u: 560 + 360 * math.sin(math.pi * min(1, u * 1.6)) - 160 * u, 0.09)
    return buk + gap + bawk


def click():
    return tone(2200, 0.025, math.sin, lambda i, T: env_ad(i, T, 0.0005, 4))


def main():
    for k in range(1, 7):
        write(f"creak_{k}", creak(k), 0.6)
    write("twang", twang())
    write("whoosh", whoosh(), 0.5)
    write("thunk_dirt", thunk(False))
    write("thunk_wood", thunk(True))
    write("thwack", thwack())
    write("grunt", grunt(), 0.6)
    write("bonk", bonk(), 0.7)
    write("clang", clang(), 0.7)
    write("ooh", ooh(), 0.55)
    write("toss_spin", toss_spin(), 0.4)
    write("toss_click", toss_click())
    write("jingle_round", jingle_round(), 0.6)
    write("jingle_match", jingle_match(), 0.6)
    write("jingle_lose", jingle_lose(), 0.6)
    write("click", click(), 0.4)
    write("squawk", squawk(), 0.7)


if __name__ == "__main__":
    main()
