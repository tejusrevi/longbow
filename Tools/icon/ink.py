"""Hand-inked drawing helpers shared by the Longbow art scripts.

Every line is rendered as a filled brush stroke with a little wobble, pressure variation and tapered
ends, and the halftone dots are slightly misregistered, so it reads hand-inked rather than geometric.
"""
import math, random, re, sys

rng = random.Random(11)

# ---------- geometry helpers ----------

def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

def bez(s, t):
    p0, p1, p2, p3 = s
    u = 1 - t
    return (u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1])

def parse(d):
    """Absolute M/L/C/Z path data -> list of (points, closed)."""
    toks = re.findall(r"[MLCZ]|-?\d+(?:\.\d+)?", d)
    subs, cur, pos, start, cmd, i = [], None, None, None, None, 0
    def close_line():
        if math.dist(pos, start) > 0.5:
            cur["segs"].append((pos, lerp(pos, start, 1 / 3), lerp(pos, start, 2 / 3), start))
    while i < len(toks):
        t = toks[i]
        if t in "MLCZ":
            cmd = t; i += 1
            if t == "Z":
                close_line(); cur["closed"] = True; pos = start
            continue
        n = lambda k: float(toks[i + k])
        if cmd == "M":
            pos = start = (n(0), n(1)); i += 2
            cur = {"segs": [], "closed": False}; subs.append(cur); cmd = "L"
        elif cmd == "L":
            p = (n(0), n(1)); i += 2
            cur["segs"].append((pos, lerp(pos, p, 1 / 3), lerp(pos, p, 2 / 3), p)); pos = p
        else:
            c1, c2, p = (n(0), n(1)), (n(2), n(3)), (n(4), n(5)); i += 6
            cur["segs"].append((pos, c1, c2, p)); pos = p
    out = []
    for sp in subs:
        pts = [sp["segs"][0][0]]
        for s in sp["segs"]:
            approx = math.dist(s[0], s[1]) + math.dist(s[1], s[2]) + math.dist(s[2], s[3])
            k = max(3, int(approx / 5))
            pts += [bez(s, j / k) for j in range(1, k + 1)]
        if sp["closed"]:
            pts = pts[:-1]
        out.append((pts, sp["closed"]))
    return out

def ellipse(cx, cy, rx, ry):
    k = 0.5523
    return (f"M{cx + rx} {cy} C{cx + rx} {cy + ry * k} {cx + rx * k} {cy + ry} {cx} {cy + ry} "
            f"C{cx - rx * k} {cy + ry} {cx - rx} {cy + ry * k} {cx - rx} {cy} "
            f"C{cx - rx} {cy - ry * k} {cx - rx * k} {cy - ry} {cx} {cy - ry} "
            f"C{cx + rx * k} {cy - ry} {cx + rx} {cy - ry * k} {cx + rx} {cy} Z")

def noise(spacing):
    """Smooth 1D value noise in -1..1 over arclength."""
    vals = [rng.uniform(-1, 1) for _ in range(400)]
    def f(s):
        x = s / spacing; i = int(x) % 399; t = x - int(x)
        t = (1 - math.cos(t * math.pi)) / 2
        return vals[i] * (1 - t) + vals[i + 1] * t
    return f

def arclen(pts):
    s = [0.0]
    for a, b in zip(pts, pts[1:]):
        s.append(s[-1] + math.dist(a, b))
    return s

def normals(pts, closed):
    n = len(pts); out = []
    for i in range(n):
        a = pts[i - 1] if (closed or i > 0) else pts[i]
        b = pts[(i + 1) % n] if (closed or i < n - 1) else pts[i]
        dx, dy = b[0] - a[0], b[1] - a[1]
        m = math.hypot(dx, dy) or 1
        out.append((-dy / m, dx / m))
    return out

def wobble(pts, closed, amp=2.6):
    f = noise(60); s = arclen(pts); ns = normals(pts, closed)
    return [(p[0] + n[0] * amp * f(si), p[1] + n[1] * amp * f(si)) for p, n, si in zip(pts, ns, s)]

def brush(pts, closed, w, taper=34, overshoot=16):
    """Filled polygon for an inked stroke along pts."""
    if closed:  # draw closed shapes as one stroke that overlaps its own start a touch
        s0 = arclen(pts + [pts[0]])
        extra = [p for p, si in zip(pts, s0) if si < overshoot]
        pts = pts + [pts[0]] + extra[1:]
    s = arclen(pts); S = s[-1] or 1
    pressure = noise(90)
    ns = normals(pts, False)
    left, right = [], []
    for i, (p, n, si) in enumerate(zip(pts, ns, s)):
        t = min(1.0, (si / taper) ** 0.5, ((S - si) / taper) ** 0.5)
        hw = w / 2 * max(0.22, t) * (1 + 0.16 * pressure(si))
        # keep sharp corners full-width (miter), clamped
        if 0 < i < len(pts) - 1:
            d1 = (pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
            m1 = math.hypot(*d1) or 1
            c = abs(n[0] * -d1[1] / m1 + n[1] * d1[0] / m1)
            hw /= max(0.55, c)
        left.append((p[0] + n[0] * hw, p[1] + n[1] * hw))
        right.append((p[0] - n[0] * hw, p[1] - n[1] * hw))
    return poly(left + right[::-1])

def poly(pts):
    return "M" + "L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + "Z"

class Shape:
    """A path drawn by hand: wobbled once, so its fill, clip and outline all agree."""
    def __init__(self, d, amp=2.6):
        self.subs = [(wobble(p, c, amp), c) for p, c in parse(d)]
    def fill(self):
        return "".join(poly(p) for p, _ in self.subs)
    def ink(self, w, **kw):
        return "".join(brush(p, c, w, **kw) for p, c in self.subs)

# ---------- halftone ----------

def halftone(fn, x0, y0, x1, y1, step=20, rmax=9.0, angle=45):
    a = math.radians(angle); ca, sa = math.cos(a), math.sin(a)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    n = int((math.hypot(x1 - x0, y1 - y0) / 2 + step) / step) + 1
    out = []
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            u, v = i * step, j * step
            x = cx + u * ca - v * sa + rng.uniform(-1.6, 1.6)
            y = cy + u * sa + v * ca + rng.uniform(-1.6, 1.6)
            if not (x0 - step <= x <= x1 + step and y0 - step <= y <= y1 + step):
                continue
            r = rmax * math.sqrt(max(0.0, min(1.0, fn(x, y)))) * rng.uniform(0.86, 1.1)
            if r < 1.3:
                continue
            out.append(f"M{x - r:.1f} {y:.1f}a{r:.1f} {r * rng.uniform(0.9, 1.05):.1f} 0 1 0 {2 * r:.1f} 0a{r:.1f} {r:.1f} 0 1 0 {-2 * r:.1f} 0")
    return "".join(out)

def ramp(x, y, ox, oy, dx, dy, start, length):
    m = math.hypot(dx, dy)
    return (((x - ox) * dx + (y - oy) * dy) / m - start) / length

