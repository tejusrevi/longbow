"""Coop-cam stills: the Longbow goose-chicken right up against a camera left in the coop.

Same character as the app icon, drawn in four cartoon styles:
    python3 make_coop.py OUT_DIR
writes coop-ink.svg, coop-sketch.svg, coop-riso.svg and coop-trailcam.svg.
"""
import math, os, sys
import ink
from ink import Shape, ellipse, halftone, ramp, poly

W = 1024

STYLES = {
    # the icon's look: black ink, white fills, black halftone on cream
    "ink": dict(paper="#F2EEE4", ink="#141414", fill="#FFFFFF", shade="#141414", accent="#141414",
                beak="#FFFFFF", bgline="#141414", wmul=1.0, amp=1.0),
    # loose pencil-ish: thin doubled lines, grey halftone, no solid blacks
    "sketch": dict(paper="#FAF8F2", ink="#2B2B2B", fill="#FAF8F2", shade="#8C8C8C", accent="none",
                   beak="#FAF8F2", bgline="#9A9A9A", wmul=0.5, amp=2.2, sketch=True),
    # two-and-a-half colour risograph: blue key line, pink and yellow layers printed slightly off
    "riso": dict(paper="#F3EEE2", ink="#24306B", fill="#F3EEE2", shade="#FF5C8A", accent="#FF5C8A",
                 beak="#FFC23A", bgline="#24306B", wmul=0.95, amp=1.2, riso=True),
    # night-vision trail camera: glowing green, eyeshine, timestamp
    "trailcam": dict(paper="#0A170E", ink="#061009", fill="#A6E39E", shade="#2F6B3A", accent="#4E9E55",
                     beak="#C8F0C0", bgline="#1F3D26", wmul=1.0, amp=1.0, night=True),
}

# ---------- the scene (shared by every style) ----------

HEAD = ("M512 250 C640 250 720 340 712 470 C706 560 662 612 642 662 "
        "C626 742 640 900 662 1080 L362 1080 C382 900 396 742 382 662 "
        "C362 612 318 560 314 470 C306 340 384 250 512 250 Z")
COMB = ("M424 292 C400 238 432 196 466 228 C462 168 532 156 534 220 "
        "C556 168 616 186 598 248 C626 246 634 280 606 300 C548 276 480 274 424 292 Z")
EYE_L, EYE_R = (432, 418, 90, 84), (600, 428, 80, 88)
PUPIL_L, PUPIL_R = (486, 444, 21, 20), (548, 440, 18, 19)   # cross-eyed at the lens
# beak points right at the lens, so it is short and foreshortened; the lower mandible hangs open below it
BEAK = "M454 490 C488 472 542 472 576 490 C566 528 540 562 515 588 C490 562 464 528 454 490 Z"
BEAK_LO = "M482 566 C496 582 506 596 515 606 C524 596 534 582 548 566 C536 590 526 602 515 610 C504 602 494 590 482 566 Z"
NOSTRILS = "M492 500 C496 498 500 498 504 500 M526 500 C530 498 534 498 538 500"
WATTLE_L = "M486 618 C462 650 462 716 490 720 C512 716 510 660 500 628 Z"
WATTLE_R = "M540 616 C566 650 566 716 538 720 C516 716 518 660 528 628 Z"
HACKLES = ("M410 760 C420 780 430 792 444 800 M600 770 C592 788 582 800 570 808 "
           "M424 860 C434 880 446 892 460 900 M590 880 C582 896 572 906 560 914 "
           "M500 820 C506 836 512 846 522 852")

# a second chicken nosing in from the right, in profile
PEEK = ("M868 236 C866 182 930 158 984 176 C1030 190 1060 210 1090 230 L1090 640 "
        "C1020 600 990 520 978 440 C930 410 870 330 868 236 Z")
PEEK_EYE, PEEK_PUPIL = (916, 252, 38, 36), (900, 260, 11, 11)
PEEK_BEAK = "M872 244 C846 250 818 258 792 268 C818 280 846 290 870 296 Z"
PEEK_COMB = "M918 176 C908 140 944 126 958 156 C970 126 1012 134 1000 172 C1026 168 1036 196 1012 210 C982 192 948 182 918 176 Z"
PEEK_WATTLE = "M880 302 C860 318 862 352 884 352 C900 348 898 322 890 306 Z"

PLANKS = "".join(f"M{x} -20 C{x + 6} 300 {x - 6} 700 {x + 4} 1060 " for x in (96, 236, 380, 652, 800, 950))
GRAIN = ("M140 120 C160 160 150 210 170 250 M300 420 C318 470 306 520 326 560 M170 640 C188 690 176 730 192 780 "
         "M700 140 C718 190 708 240 726 280 M860 560 C878 610 866 650 884 700 M720 640 C736 680 726 720 742 760")
NAILS = [(96, 160), (236, 168), (380, 150), (652, 162), (800, 156), (950, 170), (96, 880), (236, 892)]
STRAW = ("M40 1000 L120 960 M90 1010 L180 990 M150 1000 L210 940 M220 1012 L300 976 M260 990 L330 1004 "
         "M700 1000 L780 964 M740 1012 L840 990 M820 996 L880 950 M860 1012 L960 984 M930 990 L1000 1006 "
         "M960 1000 L1010 960")
FEATHER = "M150 470 C186 426 246 424 262 452 C224 490 180 496 150 470 Z"
QUILL = "M142 474 C186 466 226 458 266 450"


def render(name):
    sty = {"sketch": False, "riso": False, "night": False, **STYLES[name]}
    ink.rng.seed(23)
    defs, body, late = [], [], []
    clip_n = [0]

    def shape(d, amp=1.0):
        return Shape(d, amp=2.6 * amp * sty["amp"])

    def lines(s, d, w, amp=1.0, **kw):
        """Ink for a shape; the sketch style redraws it twice, loosely."""
        if sty["sketch"]:
            return "".join(shape(d, amp * 1.3).ink(w * sty["wmul"] * 0.8, **kw) for _ in range(2))
        return s.ink(w * sty["wmul"], **kw)

    def colour(path, fill, extra=""):
        out = f'<path d="{path}" fill="{fill}"{extra}/>'
        # riso: the coloured inks go on a second, slightly misregistered pass
        (late if sty["riso"] and fill in (sty["shade"], sty["accent"], sty["beak"]) else body).append(out)

    def piece(d, w, fill=None, dots=None, amp=1.0, line=True, **kw):
        s = shape(d, amp)
        if fill and fill != "none":
            colour(s.fill(), fill)
        if dots:
            clip_n[0] += 1
            cid = f"c{clip_n[0]}"
            defs.append(f'<clipPath id="{cid}"><path d="{s.fill()}"/></clipPath>')
            colour(dots, sty["shade"], f' clip-path="url(#{cid})"')
        if line:
            body.append(f'<path d="{lines(s, d, w, amp, **kw)}" fill="{sty["ink"]}"/>')

    def bgline(d, w, **kw):
        s = shape(d, 0.8)
        body.append(f'<path d="{lines(s, d, w, 0.8, **kw)}" fill="{sty["bgline"]}"/>')

    dot_scale = 0.7 if sty["sketch"] else 1.0

    # coop wall
    bgline(PLANKS, 14, taper=40)
    bgline(GRAIN, 7, taper=30)
    for x, y in NAILS:
        body.append(f'<path d="{shape(ellipse(x + 10, y, 6, 6), 0.4).fill()}" fill="{sty["bgline"]}"/>')

    # the nosy second chicken
    piece(PEEK_COMB, 11, sty["accent"], None if sty["accent"] != "none" else halftone(lambda x, y: 0.5, 900, 120, 1040, 220, step=12, rmax=4))
    piece(PEEK, 22, sty["fill"], halftone(lambda x, y: 0.2 + ramp(x, y, 880, 200, 0.5, 0.86, 60, 360), 840, 140, 1090, 660, rmax=9 * dot_scale))
    piece(PEEK_BEAK, 15, sty["beak"], taper=20)
    piece(PEEK_WATTLE, 10, sty["accent"])
    piece(ellipse(*PEEK_EYE), 13, sty["fill"] if not sty["night"] else "#6FAE68")
    piece(ellipse(*PEEK_PUPIL), 0, "#F6FFF2" if sty["night"] else sty["ink"], amp=0.4, line=False)

    # main chicken, right up in the lens
    piece(COMB, 13, sty["accent"], None if sty["accent"] != "none" else halftone(lambda x, y: 0.55, 400, 150, 640, 310, step=13, rmax=4.5))
    piece(HEAD, 26, sty["fill"], halftone(lambda x, y: max(ramp(x, y, 400, 330, 0.6, 0.8, 150, 360), 0.8 * ramp(x, y, 512, 700, 0, 1, 80, 360)),
                                          300, 240, 730, 1080, rmax=9 * dot_scale), taper=40)
    piece(HACKLES, 10, line=True, taper=16)
    for e in (EYE_L, EYE_R):
        piece(ellipse(*e), 16, "#6FAE68" if sty["night"] else sty["fill"])
    for p in (PUPIL_L, PUPIL_R):
        piece(ellipse(*p), 0, "#F6FFF2" if sty["night"] else sty["ink"], amp=0.4, line=False)
    piece(BEAK, 18, sty["beak"], halftone(lambda x, y: 0.7 * ramp(x, y, 514, 500, 0, 1, 20, 90), 450, 470, 580, 600, step=14, rmax=6 * dot_scale), taper=22)
    piece(BEAK_LO, 10, sty["ink"] if not sty["sketch"] else "none", taper=8)
    piece(NOSTRILS, 7, taper=4, amp=0.4)
    piece(WATTLE_L, 11, sty["accent"])
    piece(WATTLE_R, 11, sty["accent"])

    # straw in the foreground and a stray feather
    piece(STRAW, 9, taper=14)
    piece(FEATHER, 10, sty["fill"])
    piece(QUILL, 7, taper=12, amp=0.6)

    overlay = []
    if sty["riso"]:
        overlay.append(f'<g transform="translate(7 5)" style="mix-blend-mode:multiply" opacity="0.92">{"".join(late)}</g>')
    if sty["night"]:
        defs.append('<radialGradient id="vig" cx="50%" cy="48%" r="62%">'
                    '<stop offset="55%" stop-color="#000" stop-opacity="0"/><stop offset="100%" stop-color="#000" stop-opacity="0.85"/></radialGradient>'
                    '<pattern id="scan" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="4" height="1.4" fill="#000" opacity="0.22"/></pattern>'
                    '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="10"/></filter>')
        grain = "".join(f"M{ink.rng.uniform(0, W):.0f} {ink.rng.uniform(0, W):.0f}h2v2h-2z" for _ in range(3500))
        eyeshine = "".join(f'<circle cx="{e[0]}" cy="{e[1]}" r="{e[2] * 2.2}"/>' for e in (PUPIL_L, PUPIL_R, PEEK_PUPIL))
        mono = 'font-family="Menlo, Courier New, monospace" font-weight="700" fill="#D8FFD0"'
        overlay += [
            f'<g fill="#E6FFE0" opacity="0.75" filter="url(#glow)">{eyeshine}</g>',
            f'<path d="{grain}" fill="#CFFFC6" opacity="0.12"/>',
            '<rect width="1024" height="1024" fill="url(#scan)"/>',
            '<rect width="1024" height="1024" fill="url(#vig)"/>',
            f'<circle cx="74" cy="72" r="13" fill="#FF4D4D"/><text x="98" y="84" font-size="34" {mono}>REC</text>',
            f'<text x="950" y="84" font-size="30" text-anchor="end" {mono}>COOP CAM 03</text>',
            f'<text x="74" y="972" font-size="30" {mono}>10/17/2026  02:14:07</text>',
            f'<text x="950" y="972" font-size="30" text-anchor="end" {mono}>IR ON</text>',
        ]

    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" width="{W}" height="{W}">\n'
            f'<defs>{"".join(defs)}</defs>\n'
            f'<rect width="{W}" height="{W}" fill="{sty["paper"]}"/>\n'
            + "\n".join(body) + "\n" + "\n".join(overlay) + "\n</svg>\n")


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name in STYLES:
        with open(os.path.join(out, f"coop-{name}.svg"), "w") as f:
            f.write(render(name))
