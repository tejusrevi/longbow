"""Generates the Longbow app icon: a long-necked, goose-ish chicken shot clean through by a big arrow."""
import math, sys
from ink import Shape, ellipse, halftone, ramp

W = 1024
INK = "#141414"
PAPER = "#F2EEE4"

# ---------- the drawing (art space, scaled into the icon below) ----------

body = Shape("M262 236 C262 160 342 136 392 160 C440 184 440 262 414 312 "
             "C392 360 440 430 418 500 C404 548 430 584 492 576 "
             "C600 558 712 566 782 538 L866 444 C872 530 850 594 812 642 "
             "C826 762 718 864 570 864 C418 864 300 806 290 704 "
             "C282 622 330 566 312 486 C298 424 270 392 274 346 "
             "C262 316 262 280 262 236 Z")
wing = Shape("M548 604 C510 500 572 396 690 404 C668 432 704 452 680 482 "
             "C708 500 690 540 664 548 C682 572 664 602 630 612 Z")
legs = Shape("M512 856 L494 936 M494 936 L452 952 M494 936 L490 978 M494 936 L532 956 "
             "M646 850 L668 930 M668 930 L630 958 M668 930 L676 972 M668 930 L712 948")

# arrow flies left to right, straight through the middle of the body
F, A = (118, 704), (1004, 652)          # nock, tip
L = math.dist(F, A)
ux, uy = (F[0] - A[0]) / L, (F[1] - A[1]) / L
px, py = -uy, ux
def at(t, s=0.0):
    return f"{A[0] + ux * t + px * s:.1f} {A[1] + uy * t + py * s:.1f}"
shaft = Shape(f"M{at(104)} L{at(L - 10)}", amp=1.5)
head = Shape(f"M{at(0)} L{at(132, 58)} C{at(114, 28)} {at(106, 10)} {at(102, 0)} C{at(106, -10)} {at(114, -30)} {at(138, -56)} Z", amp=1.5)
fletch = Shape(f"M{at(L - 4, 2)} L{at(L + 26, 58)} L{at(L - 92, 54)} L{at(L - 128, 2)} Z "
               f"M{at(L - 4, -2)} L{at(L + 18, -62)} L{at(L - 98, -58)} L{at(L - 124, -2)} Z", amp=1.8)
vanes = Shape(f"M{at(L - 34, 4)} L{at(L - 14, 40)} M{at(L - 74, 4)} L{at(L - 56, 38)} "
              f"M{at(L - 30, -4)} L{at(L - 12, -42)} M{at(L - 72, -4)} L{at(L - 52, -40)}", amp=1)

comb = Shape("M384 166 C392 120 440 112 448 150 C470 120 512 140 494 178 C520 180 520 214 486 222 C462 206 430 196 404 194 Z")
mouth = Shape("M268 232 L264 316 L170 330 Z")
beak_up = Shape("M272 226 C210 218 150 214 100 216 C160 236 214 254 262 270 Z")
beak_lo = Shape("M262 300 C214 322 168 342 130 360 C180 354 230 344 276 334 Z")
tongue = Shape("M246 290 C210 286 196 316 168 306 C146 300 130 318 146 334 C170 356 214 332 248 310 Z")
tongue_line = Shape("M172 318 C190 316 206 308 222 300", amp=1)
wattle = Shape("M284 346 C258 360 260 404 286 404 C304 400 302 368 294 350 Z")
eye_l = Shape(ellipse(310, 176, 60, 55))
eye_r = Shape(ellipse(405, 202, 44, 47))
pupil_l = Shape(ellipse(287, 197, 14, 13), amp=1)
pupil_r = Shape(ellipse(425, 184, 11, 12), amp=1)
shock = Shape("M222 112 C214 100 204 88 196 78 M300 82 C298 66 294 52 290 40 M380 92 C388 78 396 64 404 52")
impact = Shape("M822 598 C828 584 834 572 842 558 M824 708 C832 720 840 732 848 744")
crease = Shape("M600 470 C612 456 628 446 646 440 M596 520 C612 508 628 500 648 496", amp=1.5)
feather = Shape("M780 300 C820 252 884 252 900 284 C858 324 812 330 780 300 Z")
quill = Shape("M772 304 C820 296 862 290 904 282", amp=1)
puff = Shape("M880 778 C898 748 936 746 946 766 C922 790 896 794 880 778 Z M874 782 C898 774 922 768 950 764", amp=1.5)

body_dots = halftone(lambda x, y: ramp(x, y, 420, 470, 0.5, 0.86, 150, 300), 260, 130, 920, 870)
wing_dots = halftone(lambda x, y: 0.3 + ramp(x, y, 560, 420, 0.5, 0.86, 40, 220), 500, 390, 720, 620, step=16, rmax=7)
shadow_dots = halftone(lambda x, y: 1.05 - math.hypot((x - 570) / 240, (y - 980) / 30) ** 2, 320, 940, 840, 1024, step=17, rmax=7.5)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" width="{W}" height="{W}">
  <defs>
    <clipPath id="body"><path d="{body.fill()}"/></clipPath>
    <clipPath id="wing"><path d="{wing.fill()}"/></clipPath>
  </defs>
  <rect width="{W}" height="{W}" fill="{PAPER}"/>
  <!-- art scaled in from the edges so the iOS corner mask never clips it -->
  <g transform="translate(40 66) scale(0.84)" fill="{INK}">
    <path d="{shadow_dots}" opacity="0.8"/>
    <path d="{legs.ink(22, taper=20)}"/>

    <!-- arrow first, so the body hides its middle -->
    <path d="{shaft.ink(38, taper=6)}"/>
    <path d="{head.fill()}"/>
    <path d="{head.ink(14, taper=10)}"/>
    <path d="{fletch.fill()}" fill="#fff"/>
    <path d="{fletch.ink(16, taper=18)}"/>
    <path d="{vanes.ink(8, taper=10)}"/>

    <path d="{body.fill()}" fill="#fff"/>
    <path d="{body_dots}" clip-path="url(#body)"/>
    <path d="{body.ink(25, taper=40)}"/>

    <path d="{wing.fill()}" fill="#fff"/>
    <path d="{wing_dots}" clip-path="url(#wing)"/>
    <path d="{wing.ink(21)}"/>

    <path d="{comb.fill()}"/><path d="{comb.ink(12)}"/>
    <path d="{mouth.fill()}"/><path d="{mouth.ink(12)}"/>
    <path d="{beak_up.fill()}" fill="#fff"/><path d="{beak_up.ink(18, taper=24)}"/>
    <path d="{beak_lo.fill()}" fill="#fff"/><path d="{beak_lo.ink(18, taper=24)}"/>
    <path d="{tongue.fill()}" fill="#fff"/><path d="{tongue.ink(12)}"/>
    <path d="{tongue_line.ink(7, taper=10)}"/>
    <path d="{wattle.fill()}"/><path d="{wattle.ink(10)}"/>

    <path d="{eye_l.fill()}" fill="#fff"/><path d="{eye_l.ink(15)}"/>
    <path d="{eye_r.fill()}" fill="#fff"/><path d="{eye_r.ink(15)}"/>
    <path d="{pupil_l.fill()}"/><path d="{pupil_r.fill()}"/>

    <path d="{shock.ink(17, taper=9)}"/>
    <path d="{impact.ink(14, taper=8)}"/>
    <path d="{feather.fill()}" fill="#fff"/><path d="{feather.ink(11)}"/>
    <path d="{quill.ink(8, taper=14)}"/>
    <path d="{puff.fill()}" fill="#fff"/><path d="{puff.ink(9, taper=12)}"/>
  </g>
</svg>
'''
open(sys.argv[1], "w").write(svg)
