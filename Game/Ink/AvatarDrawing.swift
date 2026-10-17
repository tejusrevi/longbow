import CoreGraphics
import LongbowCore

/// Draws an `Avatar` in the archer's head space (feet at origin, facing right).
///
/// Drawn the way an illustrator inks a caricature, not the way a computer
/// draws shapes: every line is a brush stroke that swells and tapers; the
/// head outline is heavier on the shadow side and overlaps where the pen
/// closed it; hair and beards are solid ink masses with a few paper strands;
/// features are small and simple, and personality comes from their angles
/// and a little asymmetry (the near eye sits a touch higher and larger).
/// The face is turned slightly toward where the archer looks.
enum AvatarArt {
    /// Outline weight at its heaviest; features are drawn a little lighter.
    static let line: CGFloat = 0.02
    static let pen: CGFloat = 0.015
    /// Wardrobe index for Tiger's fur (never offered as an outfit).
    static let tigerFur = 100

    struct HeadShape {
        let center: CGPoint
        let rx: CGFloat
        let ry: CGFloat
        let points: [CGPoint]
        var angular = false

        /// A point in head units: the head is roughly the unit circle.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + x * rx, y: center.y + y * ry) }

        /// Points along an arc in head units, optionally scalloped (curls).
        func arc(from a0: CGFloat, to a1: CGFloat, k: CGFloat, ky: CGFloat? = nil, cx: CGFloat = 0, cy: CGFloat = 0,
                 n: Int = 14, bumps: CGFloat = 0, depth: CGFloat = 0) -> [CGPoint] {
            (0...n).map { i in
                let t = CGFloat(i) / CGFloat(n)
                let a = a0 + (a1 - a0) * t
                let r = bumps > 0 ? 1 + depth * (abs(sin(t * .pi * bumps)) - 0.5) : 1
                return p(cx + cos(a) * k * r, cy + sin(a) * (ky ?? k) * r)
            }
        }
    }

    struct Face {
        let e1: CGPoint, e2: CGPoint, nose: CGPoint, mouth: CGPoint, earL: CGPoint, earR: CGPoint
    }

    static func shape(_ i: Int) -> HeadShape {
        let h = CharacterArt.headCenter
        func ring(_ n: Int, _ f: (CGFloat) -> CGPoint) -> [CGPoint] {
            (0..<n).map { k in f(CGFloat(k) / CGFloat(n) * 2 * .pi) }
        }
        switch i {
        case 1: // egg: a tall forehead, softly narrowing to the chin
            let c = CGPoint(x: h.x, y: h.y + 0.015)
            return HeadShape(center: c, rx: 0.215, ry: 0.28, points: ring(18) { t in
                let s = sin(t)
                let w: CGFloat = s < 0 ? 1 - 0.17 * s * s : 1
                return CGPoint(x: c.x + cos(t) * 0.215 * w, y: c.y + s * 0.28)
            })
        case 2: // square: a strong, flat jaw
            return HeadShape(center: h, rx: 0.232, ry: 0.255, points: ring(20) { t in
                let co = cos(t), s = sin(t)
                let x = copysign(pow(abs(co), 0.6), co) * 0.232 * (s < 0 ? 1 - 0.05 * -s : 1)
                let y = copysign(pow(abs(s), 0.6), s) * 0.255
                return CGPoint(x: h.x + x, y: h.y + y)
            })
        case 3: // angular: planes and corners, a chiselled chin
            let pts: [CGPoint] = [
                CGPoint(x: -0.19, y: 0.21), CGPoint(x: -0.05, y: 0.275), CGPoint(x: 0.13, y: 0.255),
                CGPoint(x: 0.235, y: 0.13), CGPoint(x: 0.24, y: -0.07), CGPoint(x: 0.14, y: -0.215),
                CGPoint(x: 0.03, y: -0.27), CGPoint(x: -0.12, y: -0.21), CGPoint(x: -0.23, y: -0.05),
            ].map { CGPoint(x: h.x + $0.x, y: h.y + $0.y) }
            return HeadShape(center: h, rx: 0.237, ry: 0.27, points: pts, angular: true)
        case 5: // chiseled: a few long planes — slim cheeks, a sharp jaw corner, a squared chin
            let pts: [CGPoint] = [
                CGPoint(x: -0.2, y: 0.2), CGPoint(x: 0.0, y: 0.29), CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.215, y: -0.12),
                CGPoint(x: 0.07, y: -0.285), CGPoint(x: -0.07, y: -0.285), CGPoint(x: -0.215, y: -0.12),
            ].map { CGPoint(x: h.x + $0.x, y: h.y + 0.01 + $0.y) }
            return HeadShape(center: CGPoint(x: h.x, y: h.y + 0.01), rx: 0.215, ry: 0.28, points: pts, angular: true)
        case 6: // broad: wide cheekbones, a square, angled jaw
            let pts: [CGPoint] = [
                CGPoint(x: -0.22, y: 0.19), CGPoint(x: 0.0, y: 0.27), CGPoint(x: 0.22, y: 0.19), CGPoint(x: 0.265, y: 0.0),
                CGPoint(x: 0.24, y: -0.15), CGPoint(x: 0.1, y: -0.26), CGPoint(x: -0.1, y: -0.26), CGPoint(x: -0.24, y: -0.15),
                CGPoint(x: -0.265, y: 0.0),
            ].map { CGPoint(x: h.x + $0.x, y: h.y + $0.y) }
            return HeadShape(center: h, rx: 0.265, ry: 0.265, points: pts, angular: true)
        case 4: // heart: full cheeks to a pointed chin
            return HeadShape(center: h, rx: 0.245, ry: 0.27, points: ring(22) { t in
                let s = sin(t)
                let w: CGFloat = s < 0 ? 1 - 0.88 * pow(-s, 2.3) : 1.03
                let y = s < 0 ? s * 0.27 - 0.03 * pow(-s, 10) : s * 0.25
                return CGPoint(x: h.x + cos(t) * 0.245 * w, y: h.y + y)
            })
        default: // round
            return HeadShape(center: h, rx: 0.235, ry: 0.255, points: ring(16) { t in
                CGPoint(x: h.x + cos(t) * 0.235, y: h.y + sin(t) * 0.255)
            })
        }
    }

    static func face(_ s: HeadShape) -> Face {
        let fx = s.center.x + s.rx * 0.16
        let ey = s.center.y + s.ry * 0.08
        return Face(e1: CGPoint(x: fx - 0.07, y: ey), e2: CGPoint(x: fx + 0.077, y: ey + 0.005),
                    nose: CGPoint(x: fx + 0.012, y: s.center.y - s.ry * 0.18),
                    mouth: CGPoint(x: fx + 0.004, y: s.center.y - s.ry * 0.53),
                    earL: s.p(-0.99, -0.06), earR: s.p(0.985, -0.05))
    }

    /// Skin is a fine halftone screen, never a colour (the game is black and white).
    static func skinPaint(_ i: Int) -> InkPaint {
        [InkPaint.paper, .dots(0.07), .dots(0.15), .dots(0.24), .dots(0.34)][min(max(i, 0), 4)]
    }

    static func draw(_ c: inout InkCanvas, _ a: Avatar, _ expr: Expression) {
        if a.tiger { return TigerArt.drawHead(&c, expr) }
        let s = shape(a.head)
        let f = face(s)
        let skin = skinPaint(a.skin)

        hairPaint = hairTonePaint(a.hairTone)
        hairOutlined = a.hairTone > 0
        drawHairBack(&c, a.hair, s)
        drawBeardBack(&c, a.facialHair, s)
        if !a.coversHead {
            ear(&c, f.earL, scale: 1, flip: false, skin: skin)
            ear(&c, f.earR, scale: 0.72, flip: true, skin: skin)
        }
        let dense = s.angular ? InkCanvas.polyline(s.points, closed: true) : InkCanvas.smoothed(s.points, closed: true)
        let headPath = CGMutablePath()
        headPath.addLines(between: dense)
        headPath.closeSubpath()
        c.fill(headPath, skin)
        c.clipped(to: headPath) { c in
            drawFacialHairInside(&c, a.facialHair, s, f, skin: skin)
            drawSkinMarks(&c, a.accessory, s, f)
        }
        c.brushLoop(s.points, width: line, angular: s.angular)
        drawHairFront(&c, a.hair, s)
        drawBeardOver(&c, a.facialHair, s, f, skin: skin)

        drawEyes(&c, a.eyes, f, expr)
        drawBrows(&c, a.brows, f, expr)
        drawNose(&c, a.nose, f.nose, skin: skin)
        if a.facialHair != 3 && a.accessory != 10 { drawMouth(&c, a.mouth, f.mouth, expr) }
        else if expr == .hit || expr == .victorious { drawMouth(&c, a.mouth, CGPoint(x: f.mouth.x, y: f.mouth.y - 0.04), expr) }
        drawMoustache(&c, a.facialHair, f)
        drawGlasses(&c, a.glasses, s, f)
        drawAccessory(&c, a.accessory, s, f, coveredEars: a.coversHead)
        if expr == .relieved { CharacterArt.sweat(&c, s.p(-1.15, 0.45)) }
    }

    /// A C-shaped ear with a little inner curl.
    private static func ear(_ c: inout InkCanvas, _ p: CGPoint, scale k: CGFloat, flip: Bool, skin: InkPaint) {
        let d: CGFloat = flip ? 1 : -1
        let pts = [CGPoint(x: p.x + d * 0.005 * k, y: p.y + 0.06 * k), CGPoint(x: p.x + d * 0.05 * k, y: p.y + 0.045 * k),
                   CGPoint(x: p.x + d * 0.06 * k, y: p.y - 0.01 * k), CGPoint(x: p.x + d * 0.035 * k, y: p.y - 0.06 * k),
                   CGPoint(x: p.x - d * 0.01 * k, y: p.y - 0.055 * k), CGPoint(x: p.x - d * 0.02 * k, y: p.y)]
        c.fill(c.path(pts, closed: true), skin)
        c.brushLoop(pts, width: pen * 0.95 * max(k, 0.8))
        c.brush([CGPoint(x: p.x + d * 0.012 * k, y: p.y + 0.028 * k), CGPoint(x: p.x + d * 0.032 * k, y: p.y + 0.008 * k),
                 CGPoint(x: p.x + d * 0.02 * k, y: p.y - 0.02 * k)], width: pen * 0.7, start: 0.3, end: 0.2)
    }

    // MARK: Hair — solid ink masses, a few paper strands for life

    private typealias U = (CGFloat, CGFloat)

    /// Paint for the hair being drawn: black is solid ink; brown, blonde and
    /// grey are halftone, with a pen outline so they still read.
    private static var hairPaint: InkPaint = .ink
    private static var hairOutlined = false

    static func hairTonePaint(_ tone: Int) -> InkPaint {
        [InkPaint.ink, .dots(0.5), .dots(0.18), .dots(0.07)][min(max(tone, 0), 3)]
    }

    private static func hairMass(_ c: inout InkCanvas, _ pts: [CGPoint], angular: Bool = false) {
        _ = c.mass(pts, paint: hairPaint, angular: angular)
        if hairOutlined { c.brushLoop(pts, width: pen * 0.8, angular: angular) }
    }

    /// Hair over the scalp: an arc over the top of the head (in head units)
    /// and a hairline back across the forehead, left to right.
    @discardableResult
    private static func cap(_ c: inout InkCanvas, _ s: HeadShape, k: CGFloat = 1.13, from aR: CGFloat = -0.22,
                            to aL: CGFloat = .pi + 0.22, hairline: [U], paint: InkPaint? = nil,
                            bumps: CGFloat = 0, depth: CGFloat = 0, angular: Bool = false) -> [CGPoint] {
        let pts = s.arc(from: aR, to: aL, k: k, n: 20, bumps: bumps, depth: depth) + hairline.map { s.p($0.0, $0.1) }
        if let paint { _ = c.mass(pts, paint: paint, angular: angular) } else { hairMass(&c, pts, angular: angular) }
        return pts
    }

    private static func strands(_ c: inout InkCanvas, _ s: HeadShape, _ lines: [[U]], width: CGFloat = pen * 0.7,
                                paint: InkPaint = .paper) {
        for l in lines { c.brush(l.map { s.p($0.0, $0.1) }, width: width, start: 0.2, end: 0.05, paint: paint) }
    }

    private static func blob(_ c: inout InkCanvas, _ s: HeadShape, _ pts: [U], paint: InkPaint? = nil,
                             outline: Bool = false) {
        let p = pts.map { s.p($0.0, $0.1) }
        if let paint { _ = c.mass(p, paint: paint) } else { hairMass(&c, p) }
        if outline { c.brushLoop(p, width: pen) }
    }

    private static let hairline: [U] = [(-1.0, -0.12), (-0.88, 0.22), (-0.62, 0.42), (-0.2, 0.5), (0.25, 0.46),
                                        (0.62, 0.42), (0.88, 0.24), (1.0, -0.1)]

    private static func drawHairBack(_ c: inout InkCanvas, _ hair: Int, _ s: HeadShape) {
        switch hair {
        case 5: // afro
            hairMass(&c, s.arc(from: 0, to: 2 * .pi, k: 1.55, ky: 1.38, cy: 0.38, n: 40, bumps: 15, depth: 0.08))
        case 6: // bun
            let b = s.p(-0.12, 1.24)
            hairMass(&c, InkCanvas.ellipsePoints(center: b, rx: 0.075, ry: 0.075, count: 12))
        case 8: // long, straight, to the shoulders
            blob(&c, s, [(-0.95, 0.6), (-1.2, 0.0), (-1.28, -0.9), (-1.12, -1.62), (-0.55, -1.5), (-0.6, -0.6)])
            blob(&c, s, [(0.95, 0.6), (1.2, 0.0), (1.26, -0.9), (1.08, -1.6), (0.55, -1.48), (0.6, -0.6)])
        case 10: // bob, cut at the jaw
            blob(&c, s, [(-0.9, 0.7), (-1.22, 0.1), (-1.25, -0.72), (-0.72, -0.78), (-0.6, 0.0)])
            blob(&c, s, [(0.9, 0.7), (1.2, 0.1), (1.2, -0.7), (0.72, -0.76), (0.6, 0.0)])
        case 11: // ponytail, swinging out behind
            blob(&c, s, [(-0.7, 0.75), (-1.35, 0.55), (-1.75, -0.2), (-1.62, -1.05), (-1.42, -0.55), (-1.15, -0.05), (-0.85, 0.2)])
        case 12: // braids, down past the shoulders
            for side in [-1.0, 1.0] as [CGFloat] {
                for k in 0..<6 {
                    let p = s.p(side * (1.02 + CGFloat(k) * 0.015), 0.05 - CGFloat(k) * 0.27)
                    hairMass(&c, InkCanvas.ellipsePoints(center: p, rx: 0.034, ry: 0.038, count: 9))
                    c.brush([CGPoint(x: p.x - 0.02, y: p.y + 0.012), CGPoint(x: p.x + 0.02, y: p.y - 0.01)],
                            width: pen * 0.5, start: 0.3, end: 0.3, paint: .paper)
                }
            }
        case 13: // locs
            for k in 0..<6 {
                let x = -1.05 + CGFloat(k) * 0.42
                let side: CGFloat = x < 0 ? -1 : 1
                c.brush([s.p(x * 0.9, 0.6), s.p(x * 1.08 + side * 0.15, -0.3), s.p(x * 1.02 + side * 0.2, -1.2 + CGFloat(k % 3) * 0.12)],
                        width: 0.058, start: 0.85, end: 0.6, paint: hairPaint)
            }
        case 14: // long waves
            for side in [-1.0, 1.0] as [CGFloat] {
                var pts: [U] = [(side * 0.9, 0.7)]
                for k in 0..<7 {
                    let y = 0.3 - CGFloat(k) * 0.3
                    pts.append((side * (1.18 + (k % 2 == 0 ? 0.0 : 0.14)), y))
                }
                pts += [(side * 0.95, -1.75), (side * 0.75, -1.2), (side * 0.65, -0.3)]
                blob(&c, s, pts)
            }
        case 15: // hijab: drape behind and under the chin, to the shoulders
            blob(&c, s, [(-1.2, 0.4), (-1.05, 1.0), (0.0, 1.32), (1.05, 1.0), (1.22, 0.3), (1.25, -0.7), (0.9, -1.45),
                         (0.0, -1.6), (-0.95, -1.45), (-1.28, -0.6)], paint: .light, outline: true)
        case 19: // space buns
            for (x, y) in [(-0.62, 1.05), (0.68, 1.08)] as [U] {
                hairMass(&c, InkCanvas.ellipsePoints(center: s.p(x, y), rx: 0.07, ry: 0.07, count: 12))
            }
        case 20: // pigtails, hanging down at each side
            blob(&c, s, [(-0.85, 0.42), (-1.22, 0.3), (-1.42, -0.4), (-1.3, -1.25), (-1.12, -0.6), (-0.95, -0.05)])
            blob(&c, s, [(0.85, 0.42), (1.22, 0.3), (1.4, -0.4), (1.28, -1.25), (1.1, -0.6), (0.95, -0.05)])
        case 21: // top knot
            hairMass(&c, InkCanvas.ellipsePoints(center: s.p(-0.02, 1.25), rx: 0.066, ry: 0.066, count: 12))
        case 23: // big curls, piled up and down to the shoulders
            hairMass(&c, s.arc(from: 0, to: 2 * .pi, k: 1.42, ky: 1.6, cy: -0.15, n: 44, bumps: 16, depth: 0.1))
        case 24: // curly fringe: one curly mass from the crown down behind the ears to the jaw
            hairMass(&c, s.arc(from: -0.62, to: .pi + 0.62, k: 1.3, ky: 1.28, cy: 0.12, n: 40, bumps: 18, depth: 0.1) +
                     [s.p(-0.98, -0.62), s.p(0.0, 0.0), s.p(0.98, -0.62)])
            curls(&c, s, [(-1.2, 0.05), (-1.18, -0.38), (1.2, 0.08), (1.17, -0.36)])
        case 26: // flowing: long, loose waves over the shoulders, tips flicking out
            for side in [-1.0, 1.0] as [CGFloat] {
                var pts: [U] = [(side * 0.85, 0.75), (side * 1.12, 0.35)]
                for k in 0..<5 {
                    let y = 0.0 - CGFloat(k) * 0.34
                    pts.append((side * (1.22 + (k % 2 == 0 ? 0.1 : -0.02)), y))
                }
                pts += [(side * 1.45, -1.85), (side * 1.05, -1.95), (side * 0.9, -1.55), (side * 0.75, -0.7), (side * 0.7, 0.1)]
                blob(&c, s, pts)
            }
        case 28: // big curly mop, round and full
            hairMass(&c, s.arc(from: 0, to: 2 * .pi, k: 1.38, ky: 1.1, cy: 0.35, n: 44, bumps: 15, depth: 0.12))
        case 29: // low bun at the back
            let b = s.p(-1.08, 0.12)
            hairMass(&c, InkCanvas.ellipsePoints(center: b, rx: 0.085, ry: 0.08, count: 12))
        case 30: // messy waves: volume at the sides, over the ears
            hairMass(&c, s.arc(from: -0.55, to: .pi + 0.55, k: 1.22, ky: 1.18, cy: 0.12, n: 24, bumps: 7, depth: 0.12))
        default:
            break
        }
    }

    private static func drawHairFront(_ c: inout InkCanvas, _ hair: Int, _ s: HeadShape) {
        let h = hairline
        switch hair {
        case 0: // bald: a little shine
            c.brush([s.p(-0.55, 0.72), s.p(-0.35, 0.86), s.p(-0.12, 0.92)], width: pen * 0.6, start: 0.2, end: 0.1)
        case 1: // one stubborn curl
            c.brush([s.p(-0.05, 0.96), s.p(-0.14, 1.2), s.p(0.04, 1.34), s.p(0.17, 1.22), s.p(0.06, 1.12), s.p(0.0, 1.2)],
                    width: pen * 1.2, start: 0.6, end: 0.1)
        case 2: // buzz: a fine dotted cap
            let pts = cap(&c, s, k: 1.03, hairline: [(-1.0, -0.05), (-0.82, 0.32), (-0.3, 0.5), (0.2, 0.48), (0.75, 0.38), (1.0, -0.03)],
                          paint: .dense)
            c.brush(Array(pts.suffix(6)), width: pen * 0.5, start: 0.3, end: 0.3)
        case 3: // comb-over: wings above the ears and a few brave strands
            blob(&c, s, [(-1.04, 0.42), (-0.86, 0.6), (-0.68, 0.48), (-0.84, 0.1), (-1.02, -0.05)])
            blob(&c, s, [(1.03, 0.38), (0.86, 0.56), (0.72, 0.44), (0.86, 0.1), (1.0, -0.02)])
            for (k, dy) in ([0.0, 0.08, 0.16] as [CGFloat]).enumerated() {
                c.brush([s.p(-0.78, 0.62 + dy), s.p(-0.2, 1.0 + dy * 0.5), s.p(0.45, 0.96 - CGFloat(k) * 0.04), s.p(0.75, 0.78)],
                        width: pen * 0.75, start: 0.5, end: 0.1)
            }
        case 4: // curly mop
            cap(&c, s, k: 1.14, from: -0.25, to: .pi + 0.25,
                hairline: [(-1.02, -0.05), (-0.9, 0.3), (-0.62, 0.38), (-0.4, 0.52), (-0.12, 0.42), (0.15, 0.55), (0.42, 0.43),
                           (0.68, 0.52), (0.92, 0.3), (1.03, -0.05)], bumps: 9, depth: 0.16)
            curls(&c, s, [(-0.55, 0.85), (0.1, 0.95), (0.6, 0.78), (-0.15, 0.68)])
        case 5: // afro hairline
            cap(&c, s, k: 1.05, from: -0.3, to: .pi + 0.3, hairline: [(-1.0, -0.1), (-0.85, 0.3), (-0.4, 0.45), (0.1, 0.42), (0.6, 0.4), (0.9, 0.3), (1.0, -0.1)],
                bumps: 6, depth: 0.05)
            curls(&c, s, [(-1.1, 1.1), (-0.3, 1.3), (0.6, 1.25), (1.2, 0.8), (-1.3, 0.3), (1.35, 0.1)])
        case 6: // bun
            cap(&c, s, hairline: h)
            c.brush([s.p(-0.28, 1.0), s.p(-0.12, 1.06), s.p(0.06, 1.0)], width: pen * 0.9, start: 0.4, end: 0.4, paint: .paper)
            strands(&c, s, [[(-0.6, 0.62), (-0.3, 0.86), (-0.12, 0.98)], [(0.4, 0.58), (0.2, 0.84), (0.0, 0.98)]])
        case 7: // mohawk, sides shaved
            c.clipped(to: headClip(s)) { c in
                c.stipple(in: CGRect(x: s.p(-1, 0.4).x, y: s.p(0, 0.4).y, width: s.rx * 2, height: s.ry * 0.7), count: 70,
                          radius: 0.004)
            }
            blob(&c, s, [(-0.45, 0.9), (-0.55, 1.28), (-0.2, 1.62), (0.35, 1.72), (0.62, 1.55), (0.42, 1.38), (0.45, 0.92),
                         (0.1, 1.0)])
            strands(&c, s, [[(-0.3, 1.2), (0.1, 1.5), (0.45, 1.6)], [(-0.1, 1.08), (0.2, 1.3)]])
        case 8: // long, centre part
            cap(&c, s, k: 1.08, from: -0.45, to: .pi + 0.45,
                hairline: [(-1.02, -0.35), (-0.88, 0.2), (-0.5, 0.5), (-0.05, 0.62), (0.05, 0.62), (0.5, 0.5), (0.88, 0.2), (1.02, -0.35)])
            strands(&c, s, [[(0.0, 0.64), (-0.04, 0.85), (-0.02, 1.06)], [(-0.4, 0.62), (-0.75, 0.6), (-0.95, 0.1)],
                            [(0.45, 0.58), (0.8, 0.5), (0.95, 0.05)]])
        case 9: // spiky
            // Uneven, swept-forward tufts, like it was slept on.
            let tips: [(CGFloat, CGFloat, CGFloat)] = [(-0.2, 1.08, 0), (0.05, 1.42, 0.22), (0.35, 1.08, 0), (0.62, 1.38, 0.3),
                                                       (0.85, 0.95, 0), (1.1, 1.05, 0.25), (1.05, 0.55, 0)]
            var pts: [CGPoint] = [s.p(-1.02, -0.1), s.p(-1.12, 0.4), s.p(-1.05, 0.62), s.p(-0.92, 0.95), s.p(-0.62, 1.05),
                                  s.p(-0.5, 1.4), s.p(-0.35, 1.12)]
            for (a, r, lean) in tips { pts.append(s.p(a + lean * 0.3, r)) }
            pts += [(1.0, -0.08), (0.88, 0.26), (0.5, 0.44), (0.0, 0.4), (-0.5, 0.5), (-0.88, 0.25)].map { s.p($0.0, $0.1) }
            hairMass(&c, pts, angular: true)
            strands(&c, s, [[(-0.4, 0.75), (-0.1, 1.05)], [(0.3, 0.7), (0.55, 1.1)]])
        case 10: // bob, blunt fringe
            cap(&c, s, k: 1.08, from: -0.75, to: .pi + 0.75,
                hairline: [(-1.06, -0.75), (-0.82, -0.7), (-0.8, 0.3), (-0.4, 0.3), (0.3, 0.29), (0.8, 0.3), (0.82, -0.68), (1.06, -0.72)])
            strands(&c, s, [[(-0.5, 0.42), (-0.3, 0.8), (-0.05, 1.0)], [(0.3, 0.4), (0.4, 0.75), (0.55, 0.9)]])
        case 11: // ponytail: pulled back
            cap(&c, s, hairline: h)
            strands(&c, s, [[(0.6, 0.48), (0.1, 0.78), (-0.5, 0.86)], [(0.2, 0.47), (-0.3, 0.68), (-0.8, 0.6)]])
            c.brush([s.p(-1.18, 0.6), s.p(-1.32, 0.38)], width: pen * 1.6, start: 0.6, end: 0.6, paint: .paper)
        case 12, 19, 20: // centre part
            cap(&c, s, hairline: [(-1.0, -0.12), (-0.86, 0.26), (-0.4, 0.5), (-0.02, 0.6), (0.06, 0.6), (0.45, 0.5), (0.86, 0.28), (1.0, -0.1)])
            strands(&c, s, [[(0.02, 0.62), (0.0, 0.85), (0.02, 1.06)]], width: pen * 0.6)
            if hair == 19 {
                for x in [-0.62, 0.68] as [CGFloat] {
                    c.brush([s.p(x - 0.25, 0.86), s.p(x, 0.82), s.p(x + 0.25, 0.86)], width: pen * 1.1, start: 0.5, end: 0.5, paint: .paper)
                }
            }
            if hair == 20 {
                c.brush([s.p(-1.32, 0.12), s.p(-1.08, 0.06)], width: pen * 1.5, start: 0.6, end: 0.6, paint: .paper)
                c.brush([s.p(1.3, 0.12), s.p(1.06, 0.06)], width: pen * 1.5, start: 0.6, end: 0.6, paint: .paper)
            }
        case 13: // locs: cap
            cap(&c, s, k: 1.08, hairline: h)
            strands(&c, s, [[(-0.7, 0.55), (-0.4, 0.95)], [(-0.2, 0.55), (0.0, 1.0)], [(0.3, 0.5), (0.45, 0.95)]])
        case 14: // waves, swept to one side
            cap(&c, s, k: 1.08, from: -0.5, to: .pi + 0.5,
                hairline: [(-1.03, -0.4), (-0.92, 0.1), (-0.65, 0.5), (-0.2, 0.62), (0.3, 0.42), (0.7, 0.18), (0.95, -0.1), (1.04, -0.4)])
            strands(&c, s, [[(-0.4, 0.9), (0.1, 0.72), (0.55, 0.3)], [(-0.75, 0.75), (-0.2, 0.98), (0.4, 0.88)]])
        case 15: // hijab: frames the face, covers the hair and ears
            let pts = cap(&c, s, k: 1.16, from: -1.05, to: .pi + 1.05,
                          hairline: [(-0.95, -0.7), (-0.9, 0.0), (-0.72, 0.42), (-0.25, 0.6), (0.25, 0.6), (0.72, 0.42), (0.9, 0.0), (0.93, -0.7)],
                          paint: .light)
            c.brushLoop(pts, width: pen)
            strands(&c, s, [[(-0.95, 0.75), (-0.4, 1.0), (0.3, 1.05)], [(0.95, -0.3), (0.85, -0.9), (0.55, -1.3)]],
                    width: pen * 0.8, paint: .ink)
        case 16: // quiff: short sides, a big wave on top
            cap(&c, s, k: 1.03, hairline: [(-1.0, -0.05), (-0.75, 0.42), (0.0, 0.52), (0.7, 0.46), (1.0, -0.02)], paint: .dense)
            blob(&c, s, [(-0.75, 0.72), (-0.42, 1.22), (0.18, 1.5), (0.82, 1.4), (1.1, 1.02), (0.75, 0.95), (0.62, 0.62), (0.15, 0.82)])
            strands(&c, s, [[(-0.35, 1.0), (0.2, 1.3), (0.8, 1.22)], [(0.0, 0.9), (0.45, 1.12), (0.85, 1.08)]])
        case 17: // side part, swept over
            cap(&c, s, hairline: [(-1.0, -0.1), (-0.85, 0.3), (-0.55, 0.64), (-0.2, 0.55), (0.3, 0.44), (0.7, 0.36), (1.0, -0.08)])
            strands(&c, s, [[(-0.55, 0.68), (-0.62, 0.92), (-0.6, 1.08)], [(-0.4, 0.76), (0.2, 0.9), (0.75, 0.62)],
                            [(-0.25, 0.6), (0.3, 0.68), (0.82, 0.42)]])
        case 18: // pixie: short with a choppy fringe
            var line: [U] = [(-1.0, 0.0), (-0.85, 0.35)]
            for k in 0..<7 {
                let x = -0.75 + CGFloat(k) * 0.25
                line.append((x, k % 2 == 0 ? 0.24 : 0.42))
            }
            line += [(0.95, 0.3), (1.0, 0.0)]
            cap(&c, s, k: 1.06, from: -0.15, to: .pi + 0.15, hairline: line, angular: true)
            strands(&c, s, [[(-0.5, 0.95), (-0.2, 0.62)], [(0.2, 1.0), (0.35, 0.6)]])
        case 21: // top knot, short sides
            cap(&c, s, k: 1.03, hairline: h, paint: .dense)
            c.brush([s.p(-0.3, 1.02), s.p(0.25, 1.02)], width: pen * 1.4, start: 0.5, end: 0.5)
        case 22: // turban: wrapped folds and a front peak
            let pts = s.arc(from: -0.15, to: .pi + 0.15, k: 1.18, ky: 1.32, n: 20) +
                [(-1.04, 0.18), (-0.5, 0.42), (0.15, 0.32), (0.55, 0.42), (1.04, 0.2)].map { s.p($0.0, $0.1) }
            let wrap = c.mass(pts, paint: .light)
            c.clipped(to: wrap) { c in
                for k in 0..<3 {
                    let y = 0.6 + CGFloat(k) * 0.24
                    c.brush([s.p(-1.08, y + 0.2), s.p(-0.2, y + 0.05), s.p(0.6, y - 0.18), s.p(1.0, y - 0.3)], width: pen * 0.8,
                            start: 0.2, end: 0.2)
                }
            }
            c.brushLoop(pts, width: pen)
            c.brush([s.p(0.15, 0.36), s.p(0.32, 0.95), s.p(0.5, 0.4)], width: pen, start: 0.3, end: 0.3)
        case 23: // big curls: hairline
            cap(&c, s, k: 1.1, from: -0.4, to: .pi + 0.4,
                hairline: [(-1.02, -0.2), (-0.85, 0.3), (-0.5, 0.48), (-0.2, 0.38), (0.15, 0.5), (0.5, 0.4), (0.85, 0.32), (1.02, -0.2)],
                bumps: 8, depth: 0.14)
            curls(&c, s, [(-1.15, -0.4), (1.15, -0.5), (-0.4, 0.85), (0.4, 0.9), (-1.2, -1.1), (1.2, -1.1)])
        case 24: // curly fringe: a compact curly top, ringlets tumbling onto the forehead
            // Big and full: volume above and out past the sides of the head.
            // Kept short at the sides: the ears show, with neat sideburns just past them.
            hairMass(&c, s.arc(from: 0.12, to: .pi - 0.12, k: 1.42, ky: 1.32, cy: 0.12, n: 32, bumps: 13, depth: 0.12) +
                     [(-1.08, 0.42), (-1.02, 0.18), (-0.86, 0.42), (-0.6, 0.6), (-0.3, 0.58), (0.0, 0.62), (0.3, 0.58), (0.6, 0.6),
                      (0.86, 0.44), (1.02, 0.2), (1.08, 0.44)].map { s.p($0.0, $0.1) })
            // Sideburns in front of the ears, down to the top of the beard line.
            for d in [-1.0, 1.0] as [CGFloat] {
                hairMass(&c, [s.p(d * 1.03, 0.32), s.p(d * 0.9, 0.3), s.p(d * 0.88, -0.05), s.p(d * 0.96, -0.08)])
            }
            curls(&c, s, [(-0.9, 1.0), (-0.35, 1.32), (0.25, 1.35), (0.85, 1.05), (-1.2, 0.55), (1.2, 0.6), (-0.1, 0.95), (0.55, 0.85)])
            // Ringlets falling onto the forehead, above the brows: the defining feature.
            for (x, y, r) in [(-0.4, 0.6, 0.042), (-0.1, 0.56, 0.052), (0.22, 0.58, 0.046), (0.5, 0.62, 0.038)]
                as [(CGFloat, CGFloat, CGFloat)] {
                let ctr = s.p(x, y)
                let loop = (0...10).map { k -> CGPoint in
                    let t = CGFloat(k) / 10 * 1.75 * .pi + 0.5 * .pi
                    let rr = r * (1 - 0.35 * CGFloat(k) / 10)
                    return CGPoint(x: ctr.x + cos(t) * rr, y: ctr.y + sin(t) * rr * 1.1)
                }
                c.brush([CGPoint(x: ctr.x, y: ctr.y + r * 1.4)] + loop, width: pen * 1.45, start: 0.9, end: 0.35, paint: hairPaint)
            }
        case 25: // tousled: receding at the temples, messy curls on top
            cap(&c, s, k: 1.12, from: -0.1, to: .pi + 0.1,
                hairline: [(-1.0, 0.05), (-0.86, 0.38), (-0.58, 0.66), (-0.3, 0.6), (0.0, 0.66), (0.3, 0.6), (0.58, 0.66),
                           (0.86, 0.4), (1.0, 0.07)], bumps: 8, depth: 0.2)
            curls(&c, s, [(-0.5, 0.88), (0.2, 0.95), (0.7, 0.8)])
        case 26: // flowing: pulled back off the face, loose strands framing it
            cap(&c, s, k: 1.1, from: -0.12, to: .pi + 0.12,
                hairline: [(-1.02, 0.12), (-0.88, 0.36), (-0.6, 0.56), (-0.2, 0.66), (0.1, 0.64), (0.55, 0.57), (0.88, 0.38), (1.02, 0.14)])
            strands(&c, s, [[(-0.15, 0.68), (-0.4, 0.9), (-0.85, 0.8)], [(0.1, 0.66), (0.45, 0.88), (0.85, 0.72)],
                            [(-0.2, 0.75), (-0.1, 1.0)]])
            for (x, d) in [(-0.86, -1.0), (0.86, 1.0)] as [(CGFloat, CGFloat)] {
                c.brush([s.p(x, 0.42), s.p(x + d * 0.02, 0.15), s.p(x - d * 0.04, -0.15), s.p(x + d * 0.03, -0.42)],
                        width: pen * 0.8, start: 0.6, end: 0.05)
            }
        case 27: // a baseball cap, curls peeking out at the sides
            for side in [-1.0, 1.0] as [CGFloat] {
                hairMass(&c, [s.p(side * 0.92, 0.45), s.p(side * 1.07, 0.32), s.p(side * 1.04, 0.05), s.p(side * 0.93, -0.05),
                              s.p(side * 0.86, 0.2)])
            }
            let crown = s.arc(from: -0.05, to: .pi + 0.05, k: 1.1, ky: 1.12, cy: 0.02, n: 18) +
                [s.p(-0.98, 0.32), s.p(0.0, 0.36), s.p(0.98, 0.34)]
            _ = c.mass(crown, paint: .ink)
            c.brush([s.p(0.0, 1.13), s.p(0.05, 0.7), s.p(0.1, 0.37)], width: pen * 0.5, start: 0.5, end: 0.5, paint: .paper)
            c.circle(s.p(0.0, 1.13), 0.014, fill: .paper, width: 0, count: 6)
            // The brim, pointing where the archer looks.
            _ = c.mass([s.p(0.25, 0.42), s.p(0.8, 0.44), s.p(1.38, 0.33), s.p(1.36, 0.24), s.p(0.8, 0.29), s.p(0.25, 0.3)], paint: .ink)
            c.brush([s.p(0.3, 0.34), s.p(0.85, 0.36), s.p(1.3, 0.3)], width: pen * 0.45, start: 0.4, end: 0.2, paint: .paper)
        case 28: // big curly mop: a heavy curly fringe
            cap(&c, s, k: 1.1, from: -0.3, to: .pi + 0.3,
                hairline: [(-1.02, -0.15), (-0.85, 0.25), (-0.62, 0.36), (-0.35, 0.3), (-0.08, 0.4), (0.2, 0.32), (0.5, 0.4),
                           (0.78, 0.3), (0.95, 0.2), (1.02, -0.12)], bumps: 10, depth: 0.14)
            curls(&c, s, [(-0.9, 0.95), (-0.35, 1.18), (0.3, 1.2), (0.95, 0.95), (-1.25, 0.4), (1.25, 0.45), (-0.55, 0.62), (0.4, 0.6)])
        case 29: // low bun: pulled back, centre part, a few loose bits
            cap(&c, s, hairline: [(-1.0, -0.1), (-0.86, 0.28), (-0.4, 0.52), (-0.03, 0.58), (0.05, 0.58), (0.45, 0.5), (0.86, 0.3), (1.0, -0.08)])
            strands(&c, s, [[(0.01, 0.6), (0.0, 0.85), (0.02, 1.06)], [(-0.4, 0.6), (-0.75, 0.62), (-0.95, 0.35)],
                            [(0.45, 0.58), (0.78, 0.55), (0.95, 0.32)]], width: pen * 0.55)
            c.brush([s.p(-0.92, 0.3), s.p(-0.98, 0.0), s.p(-0.9, -0.25)], width: pen * 0.7, start: 0.5, end: 0.05)
            c.brush([s.p(0.92, 0.3), s.p(0.97, 0.02), s.p(0.9, -0.2)], width: pen * 0.7, start: 0.5, end: 0.05)
        case 30: // messy waves: a fringe falling across the forehead
            cap(&c, s, k: 1.16, from: -0.45, to: .pi + 0.45,
                hairline: [(-1.03, -0.35), (-0.92, 0.1), (-0.7, 0.42), (-0.4, 0.3), (-0.1, 0.4), (0.2, 0.26), (0.48, 0.36),
                           (0.75, 0.22), (0.95, 0.05), (1.03, -0.3)], bumps: 6, depth: 0.1)
            strands(&c, s, [[(-0.6, 0.95), (-0.2, 0.7), (0.15, 0.42)], [(0.0, 1.0), (0.35, 0.7), (0.55, 0.45)],
                            [(-0.95, 0.6), (-0.8, 0.2)]])
        case 31: // swept: short, brushed up and back from the forehead
            // A neat short cut: tight at the sides, full on top, lifted at the front.
            hairMass(&c, s.arc(from: -0.05, to: .pi + 0.05, k: 1.1, ky: 1.3, cy: 0.0, n: 24, bumps: 5, depth: 0.05) +
                     [(-1.0, 0.05), (-0.88, 0.42), (-0.5, 0.56), (-0.1, 0.6), (0.3, 0.66), (0.62, 0.7), (0.85, 0.5), (1.0, 0.08)]
                        .map { s.p($0.0, $0.1) })
            strands(&c, s, [[(0.6, 0.72), (0.25, 1.0), (-0.3, 1.18)], [(0.2, 0.66), (-0.2, 0.92), (-0.6, 1.0)],
                            [(0.85, 0.6), (0.6, 0.95), (0.2, 1.2)]], width: pen * 0.6)
        case 32: // big tousled: tall, messy, swept up and over, a loose fringe off to one side
            hairMass(&c, s.arc(from: -0.1, to: .pi + 0.15, k: 1.18, ky: 1.38, cy: 0.05, n: 30, bumps: 9, depth: 0.16) +
                     [(-1.0, 0.1), (-0.88, 0.48), (-0.6, 0.62), (-0.3, 0.58), (0.0, 0.66), (0.35, 0.6), (0.62, 0.48),
                      (0.8, 0.3), (0.95, 0.38), (1.02, 0.15)].map { s.p($0.0, $0.1) })
            // Flicks sticking out of the top.
            for (x, y, dx, dy) in [(-0.75, 1.1, -0.22, 0.12), (-0.25, 1.36, -0.12, 0.14), (0.35, 1.36, 0.16, 0.13), (0.9, 1.0, 0.24, 0.08)]
                as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                c.brush([s.p(x, y), s.p(x + dx * 0.6, y + dy * 0.7), s.p(x + dx, y + dy)], width: pen * 1.3, start: 1, end: 0.05,
                        paint: hairPaint)
            }
            // A loose lock falling over the forehead.
            c.brush([s.p(0.25, 0.72), s.p(0.45, 0.52), s.p(0.5, 0.36)], width: pen * 1.6, start: 1, end: 0.1, paint: hairPaint)
            strands(&c, s, [[(-0.6, 0.9), (-0.1, 1.25), (0.5, 1.2)], [(-0.3, 0.75), (0.2, 1.0), (0.7, 0.95)]], width: pen * 0.6)
        default:
            break
        }
    }

    /// Little paper curl marks inside dark curly hair.
    private static func curls(_ c: inout InkCanvas, _ s: HeadShape, _ at: [U]) {
        for (x, y) in at {
            let p = s.p(x, y)
            c.brush([CGPoint(x: p.x - 0.02, y: p.y - 0.008), CGPoint(x: p.x - 0.005, y: p.y + 0.014),
                     CGPoint(x: p.x + 0.016, y: p.y + 0.004), CGPoint(x: p.x + 0.006, y: p.y - 0.012)],
                    width: pen * 0.6, start: 0.3, end: 0.1, paint: .paper)
        }
    }

    private static func headClip(_ s: HeadShape) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: InkCanvas.smoothed(s.points, closed: true))
        p.closeSubpath()
        return p
    }

    // MARK: Eyes

    private static func drawEyes(_ c: inout InkCanvas, _ style: Int, _ f: Face, _ expr: Expression) {
        switch expr {
        case .hit, .defeated, .focused, .blink, .victorious:
            expressionEyes(&c, f.e1, f.e2, expr)
            return
        default: break
        }
        for (i, e) in [f.e1, f.e2].enumerated() {
            let k: CGFloat = i == 1 ? 1.08 : 1 // the near eye, a touch bigger
            switch style {
            case 0: // dots
                c.ellipse(e, 0.016 * k, 0.021 * k, fill: .ink, width: 0)
            case 2: // sleepy: heavy lids
                c.ellipse(CGPoint(x: e.x + 0.004, y: e.y - 0.006), 0.015 * k, 0.013 * k, fill: .ink, width: 0)
                c.brush([CGPoint(x: e.x - 0.034, y: e.y + 0.002), CGPoint(x: e.x, y: e.y + 0.012), CGPoint(x: e.x + 0.034, y: e.y + 0.001)],
                        width: pen * 1.25, start: 0.3, end: 0.25)
            case 3: // big and round, with a highlight
                let r = 0.04 * k
                c.circle(e, r, fill: .paper, width: 0, count: 14)
                c.brushLoop(InkCanvas.ellipsePoints(center: e, rx: r, ry: r, count: 10), width: pen * 0.85)
                c.circle(CGPoint(x: e.x + 0.01, y: e.y - 0.006), 0.019 * k, fill: .ink, width: 0, count: 10)
                c.circle(CGPoint(x: e.x + 0.016, y: e.y + 0.001), 0.006, fill: .paper, width: 0, count: 6)
            case 4: // happy arcs
                c.brush([CGPoint(x: e.x - 0.03, y: e.y - 0.01), CGPoint(x: e.x, y: e.y + 0.016), CGPoint(x: e.x + 0.03, y: e.y - 0.008)],
                        width: pen * 1.15, start: 0.3, end: 0.2)
            case 5: // lashes: a winged lid
                c.ellipse(CGPoint(x: e.x + 0.002, y: e.y - 0.004), 0.015 * k, 0.019 * k, fill: .ink, width: 0)
                c.brush([CGPoint(x: e.x - 0.032, y: e.y + 0.006), CGPoint(x: e.x, y: e.y + 0.022), CGPoint(x: e.x + 0.034, y: e.y + 0.016),
                         CGPoint(x: e.x + 0.052, y: e.y + 0.032)], width: pen * 1.2, start: 0.3, end: 0.05)
            case 6: // almond
                let pts = [CGPoint(x: e.x - 0.042, y: e.y - 0.002), CGPoint(x: e.x, y: e.y + 0.02),
                           CGPoint(x: e.x + 0.042, y: e.y + 0.004), CGPoint(x: e.x, y: e.y - 0.016)]
                c.fill(c.path(pts, closed: true), .paper)
                c.brushLoop(pts, width: pen * 0.85)
                c.circle(CGPoint(x: e.x + 0.006, y: e.y + 0.002), 0.012 * k, fill: .ink, width: 0, count: 8)
            case 7: // wink
                if i == 1 {
                    c.brush([CGPoint(x: e.x - 0.03, y: e.y + 0.004), CGPoint(x: e.x, y: e.y - 0.008), CGPoint(x: e.x + 0.03, y: e.y + 0.006)],
                            width: pen * 1.2, start: 0.3, end: 0.15)
                    c.brush([CGPoint(x: e.x + 0.03, y: e.y + 0.006), CGPoint(x: e.x + 0.045, y: e.y + 0.018)], width: pen * 0.7,
                            start: 0.6, end: 0.1)
                } else {
                    c.ellipse(e, 0.016, 0.021, fill: .ink, width: 0)
                }
            case 8: // side-eye: flat lids, pupils in the corner
                let pts = [CGPoint(x: e.x - 0.036, y: e.y + 0.01), CGPoint(x: e.x + 0.036, y: e.y + 0.012),
                           CGPoint(x: e.x + 0.026, y: e.y - 0.012), CGPoint(x: e.x - 0.02, y: e.y - 0.014)]
                c.fill(c.path(pts, closed: true), .paper)
                c.circle(CGPoint(x: e.x + 0.02, y: e.y - 0.0), 0.012, fill: .ink, width: 0, count: 8)
                c.brush([CGPoint(x: e.x - 0.04, y: e.y + 0.01), CGPoint(x: e.x + 0.04, y: e.y + 0.013)], width: pen * 1.3,
                        start: 0.4, end: 0.3)
                c.brush([CGPoint(x: e.x - 0.028, y: e.y - 0.012), CGPoint(x: e.x + 0.0, y: e.y - 0.017), CGPoint(x: e.x + 0.03, y: e.y - 0.01)],
                        width: pen * 0.6, start: 0.2, end: 0.2)
            case 9: // tired: bags underneath
                c.ellipse(e, 0.014 * k, 0.017 * k, fill: .ink, width: 0)
                c.brush([CGPoint(x: e.x - 0.03, y: e.y + 0.018), CGPoint(x: e.x + 0.032, y: e.y + 0.014)], width: pen * 0.9,
                        start: 0.3, end: 0.2)
                c.brush([CGPoint(x: e.x - 0.028, y: e.y - 0.03), CGPoint(x: e.x, y: e.y - 0.042), CGPoint(x: e.x + 0.028, y: e.y - 0.03)],
                        width: pen * 0.6, start: 0.2, end: 0.2)
            case 10: // squint  > <
                let d: CGFloat = i == 0 ? 1 : -1
                c.brush([CGPoint(x: e.x - 0.024 * d, y: e.y + 0.02), CGPoint(x: e.x + 0.02 * d, y: e.y), CGPoint(x: e.x - 0.024 * d, y: e.y - 0.02)],
                        width: pen * 1.15, start: 0.3, end: 0.3)
            default: // round, pupils glancing ahead
                let r = 0.029 * k
                c.circle(e, r, fill: .paper, width: 0, count: 12)
                c.brushLoop(InkCanvas.ellipsePoints(center: e, rx: r, ry: r * 1.05, count: 9), width: pen * 0.75)
                c.circle(CGPoint(x: e.x + 0.009, y: e.y - 0.003), 0.013 * k, fill: .ink, width: 0, count: 8)
            }
        }
    }

    /// Eyes that override a face's own (hits, wins, aiming, blinking).
    static func expressionEyes(_ c: inout InkCanvas, _ e1: CGPoint, _ e2: CGPoint, _ expr: Expression) {
        for e in [e1, e2] {
            switch expr {
            case .hit: // spirals
                let pts = (0...18).map { i -> CGPoint in
                    let t = CGFloat(i) / 18 * 4.2 * .pi
                    let r = 0.032 * CGFloat(i) / 18
                    return CGPoint(x: e.x + r * cos(t), y: e.y + r * sin(t))
                }
                c.brush(pts, width: pen * 0.8, start: 0.3, end: 0.3)
            case .defeated: // X
                c.brush([CGPoint(x: e.x - 0.025, y: e.y - 0.025), CGPoint(x: e.x + 0.025, y: e.y + 0.025)], width: pen * 1.1,
                        start: 0.4, end: 0.3)
                c.brush([CGPoint(x: e.x - 0.025, y: e.y + 0.025), CGPoint(x: e.x + 0.025, y: e.y - 0.025)], width: pen * 1.1,
                        start: 0.4, end: 0.3)
            case .focused: // narrowed
                c.brush([CGPoint(x: e.x - 0.028, y: e.y + 0.004), CGPoint(x: e.x + 0.028, y: e.y)], width: pen * 1.4, start: 0.4, end: 0.3)
            case .blink:
                c.brush([CGPoint(x: e.x - 0.026, y: e.y + 0.004), CGPoint(x: e.x, y: e.y - 0.008), CGPoint(x: e.x + 0.026, y: e.y + 0.004)],
                        width: pen, start: 0.3, end: 0.3)
            case .victorious:
                c.brush([CGPoint(x: e.x - 0.028, y: e.y - 0.01), CGPoint(x: e.x, y: e.y + 0.018), CGPoint(x: e.x + 0.028, y: e.y - 0.01)],
                        width: pen * 1.2, start: 0.3, end: 0.3)
            default:
                c.ellipse(e, 0.016, 0.021, fill: .ink, width: 0)
            }
        }
    }

    // MARK: Brows — most of the personality lives here

    private static func drawBrows(_ c: inout InkCanvas, _ style: Int, _ f: Face, _ expr: Expression) {
        let lift: CGFloat = expr == .relieved || expr == .hit ? 0.022 : (expr == .focused ? -0.012 : 0)
        let e1 = f.e1, e2 = f.e2
        let y1 = e1.y + 0.068 + lift, y2 = e2.y + 0.07 + lift
        func pair(_ l: [CGPoint], _ r: [CGPoint], _ w: CGFloat, _ s0: CGFloat = 0.4, _ s1: CGFloat = 0.15) {
            c.brush(l, width: w, start: s0, end: s1)
            c.brush(r.reversed(), width: w, start: s0, end: s1) // both start at the inner end
        }
        // Each brow from its inner end (toward the nose) to its outer end.
        func b(_ e: CGPoint, _ y: CGFloat, _ dir: CGFloat, _ inner: CGFloat, _ mid: CGFloat, _ outer: CGFloat) -> [CGPoint] {
            [CGPoint(x: e.x + dir * 0.03, y: y + inner), CGPoint(x: e.x, y: y + mid), CGPoint(x: e.x - dir * 0.036, y: y + outer)]
        }
        switch style {
        case 1: // bushy
            pair(b(e1, y1, 1, 0.0, 0.008, -0.004), b(e2, y2, -1, 0.0, 0.008, -0.004).reversed(), pen * 1.9, 0.6, 0.15)
            for e in [e1, e2] {
                for dx in [-0.02, 0.0, 0.02] as [CGFloat] {
                    let y = (e.x == e1.x ? y1 : y2) + 0.012
                    c.brush([CGPoint(x: e.x + dx, y: y), CGPoint(x: e.x + dx + 0.006, y: y + 0.01)], width: pen * 0.5, start: 0.6, end: 0.1)
                }
            }
        case 2: // bold arch
            pair(b(e1, y1, 1, -0.004, 0.014, -0.006), b(e2, y2, -1, -0.004, 0.014, -0.006).reversed(), pen * 1.7)
        case 3: // worried: inner ends lifted
            pair(b(e1, y1, 1, 0.018, 0.006, -0.008), b(e2, y2, -1, 0.018, 0.006, -0.008).reversed(), pen * 1.3)
        case 4: // unibrow
            c.brush([CGPoint(x: e1.x - 0.04, y: y1 - 0.004), CGPoint(x: e1.x + 0.01, y: y1 + 0.006),
                     CGPoint(x: (e1.x + e2.x) / 2, y: y1 - 0.003), CGPoint(x: e2.x - 0.01, y: y2 + 0.006),
                     CGPoint(x: e2.x + 0.042, y: y2 - 0.004)], width: pen * 2, start: 0.3, end: 0.3, swell: 0.15)
        case 5: // thin, high arch
            pair(b(e1, y1 + 0.016, 1, -0.006, 0.012, -0.004), b(e2, y2 + 0.016, -1, -0.006, 0.012, -0.004).reversed(), pen * 0.8)
        case 6: // angry: inner ends pulled down
            pair(b(e1, y1, 1, -0.018, 0.0, 0.01), b(e2, y2, -1, -0.018, 0.0, 0.01).reversed(), pen * 1.7, 0.5, 0.2)
        case 7: // quizzical: one up, one flat
            c.brush(b(e1, y1 - 0.004, 1, 0, 0, 0), width: pen * 1.3, start: 0.4, end: 0.15)
            c.brush(b(e2, y2 + 0.016, -1, -0.006, 0.02, 0.0), width: pen * 1.3, start: 0.4, end: 0.15)
        case 8: // thick and straight
            pair(b(e1, y1, 1, 0, 0.002, 0), b(e2, y2, -1, 0, 0.002, 0).reversed(), pen * 2.6, 0.9, 0.7)
        case 9: // two dots, high and surprised
            for e in [e1, e2] { c.ellipse(CGPoint(x: e.x, y: e.y + 0.085 + lift), 0.016, 0.011, fill: .ink, width: 0) }
        default: // soft
            pair(b(e1, y1, 1, 0, 0.006, -0.004), b(e2, y2, -1, 0, 0.006, -0.004).reversed(), pen * 1.05)
        }
    }

    // MARK: Nose — usually one confident line

    private static func drawNose(_ c: inout InkCanvas, _ style: Int, _ n: CGPoint, skin: InkPaint) {
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: n.x + x, y: n.y + y) }
        switch style {
        case 1: // bulb
            let pts = InkCanvas.ellipsePoints(center: P(0.02, -0.004), rx: 0.052, ry: 0.046, count: 10)
            c.fill(c.path(pts, closed: true), skin)
            c.brushLoop(pts, width: pen)
            c.brush([P(-0.008, -0.024), P(0.004, -0.032)], width: pen * 0.8, start: 0.5, end: 0.3)
        case 2: // long
            c.brush([P(-0.02, 0.09), P(0.02, 0.02), P(0.05, -0.028), P(0.03, -0.042), P(0.0, -0.036)], width: pen,
                    start: 0.15, end: 0.3)
        case 3: // just nostrils
            c.brush([P(-0.012, -0.012), P(-0.004, -0.022)], width: pen * 1.1, start: 0.8, end: 0.4)
            c.brush([P(0.03, -0.012), P(0.022, -0.022)], width: pen * 1.1, start: 0.8, end: 0.4)
        case 4: // small
            c.brush([P(0.0, 0.016), P(0.016, -0.008), P(0.0, -0.016)], width: pen * 0.9, start: 0.2, end: 0.4)
        case 5: // snub, upturned
            c.brush([P(-0.01, 0.06), P(0.03, 0.0), P(0.05, -0.004), P(0.042, -0.03), P(0.006, -0.03)], width: pen,
                    start: 0.15, end: 0.3)
            c.ellipse(P(0.03, -0.018), 0.008, 0.006, fill: .ink, width: 0)
        case 6: // roman: a bump on the bridge
            c.brush([P(-0.03, 0.1), P(0.015, 0.06), P(0.025, 0.04), P(0.065, -0.03), P(0.03, -0.042), P(0.0, -0.035)],
                    width: pen, start: 0.15, end: 0.3)
        case 7: // potato
            let pts = [P(-0.04, -0.012), P(-0.025, 0.028), P(0.012, 0.016), P(0.05, 0.034), P(0.072, -0.008),
                       P(0.045, -0.042), P(-0.012, -0.04)]
            c.fill(c.path(pts, closed: true), skin)
            c.brushLoop(pts, width: pen)
        case 8: // wedge
            c.brush([P(0.0, 0.07), P(0.055, -0.03), P(-0.02, -0.032)], width: pen, start: 0.2, end: 0.3)
        case 9: // pinocchio
            let pts = [P(-0.01, 0.026), P(0.2, 0.0), P(-0.01, -0.03)]
            c.fill(c.polygon(pts), skin)
            c.brush([P(-0.01, 0.026), P(0.2, 0.0), P(-0.01, -0.03)], width: pen * 0.9, start: 0.2, end: 0.2, swell: 0.1)
        case 10: // beak, hooked
            c.brush([P(-0.02, 0.07), P(0.045, 0.03), P(0.06, -0.025), P(0.035, -0.06), P(0.03, -0.035), P(0.0, -0.035)],
                    width: pen, start: 0.15, end: 0.3)
        default: // button: a little hook
            c.brush([P(-0.004, 0.02), P(-0.01, -0.008), P(0.01, -0.02), P(0.028, -0.008)], width: pen, start: 0.25, end: 0.2)
        }
    }

    // MARK: Mouth

    private static func drawMouth(_ c: inout InkCanvas, _ style: Int, _ m: CGPoint, _ expr: Expression) {
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: m.x + x, y: m.y + y) }
        switch expr {
        case .hit:
            let pts = InkCanvas.ellipsePoints(center: m, rx: 0.036, ry: 0.034, count: 9)
            c.fill(c.path(pts, closed: true), .ink)
            return
        case .victorious:
            let pts = [P(-0.07, 0.016), P(0.07, 0.016), P(0.035, -0.045), P(-0.035, -0.045)]
            c.fill(c.path(pts, closed: true), .ink)
            c.brush([P(-0.05, 0.004), P(0.05, 0.004)], width: pen * 0.6, start: 0.4, end: 0.4, paint: .paper)
            return
        case .defeated:
            c.brush([P(-0.055, -0.012), P(-0.02, 0.008), P(0.02, -0.008), P(0.055, 0.01)], width: pen, start: 0.3, end: 0.3)
            return
        case .focused:
            c.brush([P(-0.04, 0.002), P(0.04, -0.002)], width: pen * 1.1, start: 0.3, end: 0.3)
            return
        default: break
        }
        switch style {
        case 1: // flat
            c.brush([P(-0.046, 0.002), P(0.0, -0.002), P(0.046, 0.003)], width: pen, start: 0.3, end: 0.4)
        case 2: // grin with teeth
            let pts = [P(-0.065, 0.016), P(0.065, 0.016), P(0.03, -0.035), P(-0.03, -0.035)]
            c.fill(c.path(pts, closed: true), .ink)
            c.fill(c.path([P(-0.056, 0.012), P(0.056, 0.012), P(0.045, -0.006), P(-0.045, -0.006)], closed: true), .paper)
        case 3: // smirk
            c.brush([P(-0.045, 0.002), P(0.01, -0.01), P(0.05, 0.016)], width: pen, start: 0.3, end: 0.15)
            c.brush([P(0.05, 0.016), P(0.06, 0.006)], width: pen * 0.7, start: 0.5, end: 0.2)
        case 4: // oh
            let pts = InkCanvas.ellipsePoints(center: m, rx: 0.017, ry: 0.022, count: 8)
            c.fill(c.path(pts, closed: true), .ink)
        case 5: // full lips
            let upper = [P(-0.05, 0.0), P(-0.02, 0.02), P(0.0, 0.012), P(0.02, 0.02), P(0.05, 0.0)]
            let lower = [P(0.05, 0.0), P(0.02, -0.03), P(-0.02, -0.03), P(-0.05, 0.0)]
            c.fill(c.path(lower + [P(-0.05, 0.0)], closed: true), .dense)
            c.brush(upper, width: pen * 0.9, start: 0.3, end: 0.3)
            c.brush(lower, width: pen * 0.9, start: 0.3, end: 0.3)
            c.brush([P(-0.045, 0.0), P(0.045, 0.0)], width: pen * 0.8, start: 0.4, end: 0.4)
        case 6: // cheeky: tongue out
            c.brush([P(-0.055, 0.012), P(0.0, -0.014), P(0.055, 0.012)], width: pen, start: 0.3, end: 0.2)
            let t = [P(-0.004, -0.012), P(0.034, -0.008), P(0.03, -0.05), P(0.004, -0.046)]
            c.fill(c.path(t, closed: true), .paper)
            c.brushLoop(t, width: pen * 0.75)
            c.brush([P(0.016, -0.014), P(0.016, -0.034)], width: pen * 0.5, start: 0.3, end: 0.3)
        case 7: // laugh: wide open
            let pts = [P(-0.07, 0.018), P(0.07, 0.018), P(0.04, -0.055), P(-0.04, -0.055)]
            let open = c.path(pts, closed: true)
            c.fill(open, .ink)
            c.clipped(to: open) { c in c.ellipse(P(0.006, -0.05), 0.036, 0.018, fill: .paper, width: 0) }
        case 8: // buck teeth
            c.brush([P(-0.05, 0.012), P(0.0, -0.006), P(0.05, 0.012)], width: pen, start: 0.3, end: 0.3)
            let teeth = [P(-0.022, -0.004), P(0.022, -0.004), P(0.02, -0.038), P(-0.02, -0.038)]
            c.fill(c.polygon(teeth), .paper)
            c.brushLoop(teeth, width: pen * 0.7, angular: true)
            c.brush([P(0.0, -0.006), P(0.0, -0.036)], width: pen * 0.5, start: 0.4, end: 0.4)
        case 10: // beaming: a big, wide, warm smile with a row of teeth
            let pts = [P(-0.085, 0.022), P(-0.04, 0.008), P(0.0, 0.006), P(0.04, 0.008), P(0.085, 0.022),
                       P(0.06, -0.025), P(0.0, -0.042), P(-0.06, -0.025)]
            let open = c.path(pts, closed: true)
            c.fill(open, .paper)
            c.clipped(to: open) { c in
                c.fill(c.path([P(-0.1, -0.022), P(0.1, -0.022), P(0.1, -0.06), P(-0.1, -0.06)], closed: true), .ink)
            }
            c.brushLoop(pts, width: pen * 0.9)
            for d in [-1.0, 1.0] as [CGFloat] {
                c.brush([P(d * 0.098, 0.034), P(d * 0.088, 0.018), P(d * 0.094, 0.004)], width: pen * 0.6, start: 0.4, end: 0.2)
            }
        case 9: // wobbly
            c.brush([P(-0.05, 0.0), P(-0.025, 0.01), P(0.0, -0.006), P(0.025, 0.01), P(0.05, 0.0)], width: pen,
                    start: 0.3, end: 0.3)
        default: // smile, with little dimples
            c.brush([P(-0.058, 0.014), P(-0.02, -0.014), P(0.025, -0.014), P(0.06, 0.016)], width: pen * 1.05,
                    start: 0.25, end: 0.2)
            c.brush([P(-0.066, 0.02), P(-0.056, 0.006)], width: pen * 0.6, start: 0.4, end: 0.2)
        }
    }

    // MARK: Facial hair — ink masses that hug the jaw, a gap for the mouth

    /// Jaw-hugging beard outline in head units, from ear to ear under the chin.
    private static func jaw(_ s: HeadShape, top: CGFloat, drop: CGFloat, chin: CGFloat = 0) -> [U] {
        var pts: [U] = [(-1.0, top), (-0.97, top - 0.3)]
        for k in 0...8 {
            let a = CGFloat.pi * (1.15 + 0.7 * CGFloat(k) / 8)
            let extra = k == 4 ? chin : (k == 3 || k == 5 ? chin * 0.6 : 0)
            pts.append((cos(a) * (1.02 + drop * 0.3), sin(a) * (1.02 + drop) - extra))
        }
        pts += [(0.97, top - 0.3), (1.0, top)]
        // Back up along the cheeks, under the moustache line.
        pts += [(0.62, top - 0.18), (0.25, -0.38), (0.0, -0.36), (-0.4, -0.3), (-0.75, top - 0.15)]
        return pts
    }

    private static func drawBeardBack(_ c: inout InkCanvas, _ style: Int, _ s: HeadShape) {
        switch style {
        default: break
        }
    }

    /// Facial hair that sits on the skin (clipped to the head).
    /// Stubble reads as shadow: a fine dot screen a step darker than the
    /// skin, over the jaw, chin and upper lip, clear of the lips themselves.
    private static func stubble(_ c: inout InkCanvas, _ s: HeadShape, _ f: Face, skin: InkPaint, light: Bool = false) {
        var base = 0.0
        if case let .dots(d) = skin { base = d }
        let shade = InkPaint.dots(min(0.62, base + (light ? 0.1 : 0.2)))
        let region = CGMutablePath()
        region.addLines(between: InkCanvas.smoothed(jaw(s, top: -0.12, drop: 0.0).map { s.p($0.0, $0.1) }, closed: true))
        region.closeSubpath()
        c.fill(region, shade)
        // Upper lip.
        c.fill(c.path([CGPoint(x: f.mouth.x - 0.075, y: f.mouth.y + 0.01), CGPoint(x: f.mouth.x, y: f.mouth.y + 0.05),
                       CGPoint(x: f.mouth.x + 0.075, y: f.mouth.y + 0.01), CGPoint(x: f.mouth.x, y: f.mouth.y + 0.022)], closed: true), shade)
        // Keep the lips clean.
        c.ellipse(CGPoint(x: f.mouth.x, y: f.mouth.y - 0.006), 0.06, 0.022, fill: skin, width: 0)
    }

    private static func drawFacialHairInside(_ c: inout InkCanvas, _ style: Int, _ s: HeadShape, _ f: Face, skin: InkPaint) {
        switch style {
        case 1, 13: // stubble: a soft halftone shadow along the jaw and lip
            stubble(&c, s, f, skin: skin)
        case 14: // faint beard: a light shadow and a fine line tracing the jaw
            stubble(&c, s, f, skin: skin, light: true)
            c.brush(s.arc(from: .pi * 1.06, to: .pi * 1.94, k: 0.97, ky: 0.97, cy: -0.03, n: 14), width: pen * 0.55,
                    start: 0.1, end: 0.1, swell: 0.3)
        case 7: // short beard: drawn over the jaw (see drawBeardOver)
            break
        case 9: // chinstrap: one bold stroke right along the jaw
            c.brush(s.arc(from: .pi * 0.98, to: .pi * 2.02, k: 0.95, ky: 0.95, cy: -0.02, n: 14), width: 0.034,
                    start: 0.3, end: 0.3, swell: 0.2)
        case 10: // mutton chops
            for side in [-1.0, 1.0] as [CGFloat] {
                blob(&c, s, [(side * 1.05, 0.08), (side * 0.8, 0.02), (side * 0.62, -0.42), (side * 0.74, -0.66), (side * 1.02, -0.42)])
            }
        default: break
        }
    }

    /// Beards with volume, drawn over the jaw line.
    private static func drawBeardOver(_ c: inout InkCanvas, _ style: Int, _ s: HeadShape, _ f: Face, skin: InkPaint) {
        func mouthGap(_ w: CGFloat, _ h: CGFloat) {
            c.ellipse(CGPoint(x: f.mouth.x, y: f.mouth.y - 0.004), w, h, fill: skin, width: 0)
        }
        switch style {
        case 4: // goatee
            blob(&c, s, [(-0.12, -0.62), (0.32, -0.62), (0.28, -0.95), (0.12, -1.18), (-0.06, -0.95)])
            mouthGap(0.042, 0.016)
        case 7: // short, neat and full: hugs the jaw, no volume
            // A trimmed beard: a dotted shadow along the jaw, inked at the edge.
            let pts = jaw(s, top: -0.3, drop: -0.04, chin: 0.0).map { s.p($0.0, $0.1) }
            // Always clearly darker than the skin underneath.
            var base = 0.0
            if case let .dots(d) = skin { base = d }
            _ = c.mass(pts, paint: .dots(min(0.82, max(0.55, base + 0.38))))
            c.brushLoop(pts, width: pen * 0.5)
            mouthGap(0.05, 0.02)
        case 12: // van dyke: a chin beard to go with the moustache
            blob(&c, s, [(-0.05, -0.64), (0.37, -0.64), (0.33, -0.92), (0.16, -1.08), (0.0, -0.92)])
            mouthGap(0.045, 0.016)
        case 5: // full beard, with a little volume under the chin
            _ = c.mass(jaw(s, top: -0.12, drop: 0.12, chin: 0.1).map { s.p($0.0, $0.1) })
            strands(&c, s, [[(-0.5, -0.65), (-0.4, -0.95)], [(0.05, -0.85), (0.08, -1.15)], [(0.55, -0.6), (0.48, -0.9)]],
                    width: pen * 0.55)
            mouthGap(0.05, 0.02)
        case 6: // viking: long and proud, a wavy hem and two braids
            var pts: [U] = [(-1.0, -0.05), (-0.98, -0.45), (-0.82, -0.95)]
            for k in 0...6 {
                let x = -0.62 + CGFloat(k) * 0.2
                pts.append((x, -1.45 - (k % 2 == 0 ? 0.0 : 0.1) - (k == 3 ? 0.12 : 0)))
            }
            pts += [(0.95, -0.85), (1.0, -0.4), (0.98, -0.05), (0.62, -0.3), (0.25, -0.38), (0.0, -0.36), (-0.4, -0.3), (-0.75, -0.2)]
            _ = c.mass(pts.map { s.p($0.0, $0.1) })
            strands(&c, s, [[(-0.5, -0.75), (-0.42, -1.2)], [(0.05, -0.95), (0.1, -1.38)], [(0.55, -0.72), (0.48, -1.15)]],
                        width: pen * 0.55)
            for x in [-0.2, 0.42] as [CGFloat] {
                for k in 0..<3 {
                    c.ellipse(s.p(x, -1.62 - CGFloat(k) * 0.2), 0.024, 0.028, fill: .ink, width: 0)
                    c.brush([s.p(x - 0.08, -1.6 - CGFloat(k) * 0.2), s.p(x + 0.08, -1.66 - CGFloat(k) * 0.2)], width: pen * 0.4,
                            start: 0.5, end: 0.5, paint: .paper)
                }
                let bead = s.p(x, -2.24)
                _ = c.mass(InkCanvas.ellipsePoints(center: bead, rx: 0.022, ry: 0.022, count: 8), paint: .paper)
                c.brushLoop(InkCanvas.ellipsePoints(center: bead, rx: 0.022, ry: 0.022, count: 8), width: pen * 0.7)
            }
            mouthGap(0.05, 0.02)
        default: break
        }
    }

    /// Moustaches, over everything on the face.
    private static func drawMoustache(_ c: inout InkCanvas, _ style: Int, _ f: Face) {
        let m = f.mouth
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: m.x + x, y: m.y + y) }
        switch style {
        case 2: // handlebar, curled up at the tips
            c.brush([P(0.0, 0.03), P(-0.05, 0.022), P(-0.09, 0.03), P(-0.1, 0.055), P(-0.082, 0.062)], width: pen * 2,
                    start: 0.9, end: 0.15)
            c.brush([P(0.0, 0.03), P(0.05, 0.022), P(0.09, 0.03), P(0.1, 0.055), P(0.082, 0.062)], width: pen * 2,
                    start: 0.9, end: 0.15)
        case 3: // walrus: shaggy, swallowing the mouth
            var pts = [P(-0.1, 0.0), P(-0.07, 0.05), P(0.0, 0.06), P(0.07, 0.05), P(0.1, 0.0)]
            for k in 0...8 {
                let x = 0.1 - CGFloat(k) * 0.025
                pts.append(P(x, k % 2 == 0 ? -0.04 : -0.02))
            }
            _ = c.mass(pts)
        case 5, 6, 7, 10: // a neat moustache
            _ = c.mass([P(-0.065, 0.006), P(-0.03, 0.04), P(0.0, 0.03), P(0.03, 0.04), P(0.065, 0.006), P(0.0, 0.016)])
        case 12: // van dyke moustache: trim, down at the corners
            _ = c.mass([P(-0.075, -0.004), P(-0.04, 0.036), P(0.0, 0.03), P(0.04, 0.036), P(0.075, -0.004), P(0.0, 0.018)])
        case 14: // a subtle moustache: a thin, soft line
            c.brush([P(-0.06, 0.012), P(-0.03, 0.03), P(0.0, 0.026), P(0.03, 0.03), P(0.06, 0.012)], width: pen * 0.75,
                    start: 0.2, end: 0.2, swell: 0.35)
        case 13: // a bold, full moustache
            _ = c.mass([P(-0.08, 0.0), P(-0.05, 0.045), P(0.0, 0.05), P(0.05, 0.045), P(0.08, 0.0), P(0.03, 0.022),
                        P(-0.03, 0.022)])
        case 8: // pencil, with waxed points
            c.brush([P(0.0, 0.028), P(-0.05, 0.026), P(-0.1, 0.05), P(-0.115, 0.075)], width: pen * 1.1, start: 0.9, end: 0.05)
            c.brush([P(0.0, 0.028), P(0.05, 0.026), P(0.1, 0.05), P(0.115, 0.075)], width: pen * 1.1, start: 0.9, end: 0.05)
        case 11: // horseshoe
            c.brush([P(-0.06, -0.09), P(-0.068, 0.0), P(-0.03, 0.034), P(0.03, 0.034), P(0.068, 0.0), P(0.06, -0.09)],
                    width: pen * 2.1, start: 0.5, end: 0.5, swell: 0.15)
        default: break
        }
    }

    // MARK: Glasses

    private static func drawGlasses(_ c: inout InkCanvas, _ style: Int, _ s: HeadShape, _ f: Face) {
        guard style > 0 else { return }
        let r: CGFloat = 0.048
        var bridge: CGFloat = 0.008
        for (i, e) in [f.e1, f.e2].enumerated() {
            let k: CGFloat = i == 1 ? 1.04 : 1
            switch style {
            case 2: // square
                let pts = [CGPoint(x: e.x - r, y: e.y + r * 0.75), CGPoint(x: e.x + r, y: e.y + r * 0.8),
                           CGPoint(x: e.x + r * 0.95, y: e.y - r * 0.8), CGPoint(x: e.x - r * 0.95, y: e.y - r * 0.78)]
                c.brushLoop(pts, width: pen * 0.95, angular: true)
            case 3: // shades
                let pts = InkCanvas.ellipsePoints(center: CGPoint(x: e.x, y: e.y - 0.004), rx: r * 1.02, ry: r * 0.78, count: 10)
                _ = c.mass(pts)
            case 4: // aviators: tinted teardrops
                let pts = [CGPoint(x: e.x - r, y: e.y + r * 0.62), CGPoint(x: e.x + r, y: e.y + r * 0.62),
                           CGPoint(x: e.x + r * 0.92, y: e.y - r * 0.5), CGPoint(x: e.x + r * 0.1, y: e.y - r * 1.15),
                           CGPoint(x: e.x - r * 0.88, y: e.y - r * 0.45)]
                _ = c.mass(pts, paint: .dense)
                c.brushLoop(pts, width: pen * 0.7)
                bridge = 0.03
            case 5: // cat-eye
                let o: CGFloat = i == 0 ? -1 : 1
                let pts = [CGPoint(x: e.x - o * r * 0.9, y: e.y + r * 0.55), CGPoint(x: e.x + o * r * 0.2, y: e.y + r * 0.62),
                           CGPoint(x: e.x + o * r * 1.18, y: e.y + r * 1.05), CGPoint(x: e.x + o * r * 0.9, y: e.y - r * 0.55),
                           CGPoint(x: e.x - o * r * 0.6, y: e.y - r * 0.72)]
                c.brushLoop(pts, width: pen * 1.5)
            case 6: // thick rims: chunky rectangles
                let rx = r * 1.12 * k, ry = r * 0.82 * k
                let pts = [CGPoint(x: e.x - rx, y: e.y + ry), CGPoint(x: e.x + rx, y: e.y + ry * 1.04),
                           CGPoint(x: e.x + rx * 0.96, y: e.y - ry * 0.95), CGPoint(x: e.x - rx * 0.96, y: e.y - ry)]
                c.brushLoop(pts, width: pen * 2, angular: true)
            case 7: // half-moon readers, low
                let p = CGPoint(x: e.x, y: e.y - 0.03)
                c.brush(InkCanvas.ellipsePoints(center: p, rx: r * 0.85, ry: r * 0.72, count: 8, from: .pi, to: 2 * .pi) +
                        [CGPoint(x: p.x - r * 0.85, y: p.y)], width: pen * 0.9, start: 0.6, end: 0.6, swell: 0.1)
                bridge = -0.026
            case 8: // heart shades
                let pts = [CGPoint(x: e.x, y: e.y + r * 0.3), CGPoint(x: e.x - r * 0.55, y: e.y + r * 0.92),
                           CGPoint(x: e.x - r * 1.05, y: e.y + r * 0.28), CGPoint(x: e.x, y: e.y - r * 0.95),
                           CGPoint(x: e.x + r * 1.05, y: e.y + r * 0.28), CGPoint(x: e.x + r * 0.55, y: e.y + r * 0.92)]
                _ = c.mass(pts)
            case 9: // goggles
                let pts = InkCanvas.ellipsePoints(center: e, rx: r * 1.15, ry: r * 1.1, count: 12)
                _ = c.mass(pts, paint: .light)
                c.brushLoop(pts, width: pen * 1.8)
            default: // round
                c.brushLoop(InkCanvas.ellipsePoints(center: e, rx: r * k, ry: r * k, count: 10), width: pen * 0.9)
            }
        }
        let e1 = f.e1, e2 = f.e2
        if style == 9 {
            c.brush([s.p(-1.02, 0.2), CGPoint(x: e1.x - r * 1.1, y: e1.y)], width: pen * 2.6, start: 0.8, end: 0.8)
            c.brush([CGPoint(x: e1.x + r, y: e1.y), CGPoint(x: e2.x - r, y: e2.y)], width: pen * 1.6, start: 0.8, end: 0.8)
            return
        }
        c.brush([CGPoint(x: e1.x + r * 0.95, y: e1.y + bridge), CGPoint(x: (e1.x + e2.x) / 2, y: e1.y + bridge + 0.008),
                 CGPoint(x: e2.x - r * 0.95, y: e2.y + bridge)], width: pen * 0.8, start: 0.5, end: 0.5)
        c.brush([CGPoint(x: e1.x - r, y: e1.y + 0.006 + min(bridge, 0)), s.p(-0.98, 0.16)], width: pen * 0.75, start: 0.6, end: 0.3)
    }

    // MARK: Extras

    /// Marks on the skin (clipped to the head).
    private static func drawSkinMarks(_ c: inout InkCanvas, _ style: Int, _ s: HeadShape, _ f: Face) {
        switch style {
        case 1: // freckles across the nose and cheeks
            for (dx, dy) in [(-0.11, -0.05), (-0.085, -0.075), (-0.06, -0.052), (-0.03, -0.07), (0.05, -0.058), (0.08, -0.08),
                             (0.105, -0.055), (0.13, -0.078), (-0.13, -0.08)] as [(CGFloat, CGFloat)] {
                c.dot(CGPoint(x: f.nose.x + dx, y: f.nose.y + dy + 0.02), 0.0075)
            }
        case 3: // a scar through the brow
            let a = CGPoint(x: f.e2.x - 0.03, y: f.e2.y + 0.12), b = CGPoint(x: f.e2.x + 0.04, y: f.e2.y - 0.1)
            c.brush([a, b], width: pen * 1.1, start: 0.3, end: 0.3)
            for k in 0..<4 {
                let t = CGFloat(k + 1) / 5
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                c.brush([CGPoint(x: p.x - 0.02, y: p.y - 0.008), CGPoint(x: p.x + 0.02, y: p.y + 0.008)], width: pen * 0.6,
                        start: 0.4, end: 0.4)
            }
        case 8: // war paint: two swipes under each eye
            for e in [f.e1, f.e2] {
                for k in 0..<2 {
                    let y = e.y - 0.06 - CGFloat(k) * 0.035
                    c.brush([CGPoint(x: e.x - 0.04, y: y + 0.004), CGPoint(x: e.x + 0.04, y: y - 0.004)], width: 0.016,
                            start: 0.9, end: 0.2, swell: 0.1)
                }
            }
        default: break
        }
    }

    /// Things worn on or around the head.
    private static func drawAccessory(_ c: inout InkCanvas, _ style: Int, _ s: HeadShape, _ f: Face, coveredEars: Bool) {
        let lobe = CGPoint(x: f.earL.x - 0.01, y: f.earL.y - 0.06)
        switch style {
        case 2: // eye patch
            c.brush([s.p(-1.02, 0.42), CGPoint(x: f.e2.x, y: f.e2.y + 0.02), s.p(1.02, -0.02)], width: pen * 0.75, start: 0.6, end: 0.6)
            let e = f.e2
            _ = c.mass([CGPoint(x: e.x - 0.045, y: e.y + 0.035), CGPoint(x: e.x + 0.045, y: e.y + 0.04),
                        CGPoint(x: e.x + 0.04, y: e.y - 0.03), CGPoint(x: e.x, y: e.y - 0.05), CGPoint(x: e.x - 0.04, y: e.y - 0.028)])
        case 4 where !coveredEars: // big hoops
            c.brushLoop(InkCanvas.ellipsePoints(center: CGPoint(x: lobe.x - 0.005, y: lobe.y - 0.045), rx: 0.042, ry: 0.05, count: 10),
                        width: pen * 1.5)
        case 5: // headphones
            c.brush(s.arc(from: 0.05, to: .pi - 0.05, k: 1.16, ky: 1.12, n: 12), width: 0.03, start: 0.8, end: 0.8, swell: 0.1)
            for (p, d) in [(f.earL, CGFloat(-1)), (f.earR, CGFloat(1))] {
                let cup = InkCanvas.ellipsePoints(center: CGPoint(x: p.x + d * 0.02, y: p.y), rx: 0.045, ry: 0.075, count: 10)
                _ = c.mass(cup, paint: .paper)
                c.brushLoop(cup, width: pen * 1.1)
                c.ellipse(CGPoint(x: p.x + d * 0.03, y: p.y), 0.016, 0.042, fill: .ink, width: 0)
            }
        case 6: // a flower behind the ear
            let fl = CGPoint(x: f.earL.x + 0.01, y: f.earL.y + 0.1)
            for k in 0..<5 {
                let a = CGFloat(k) / 5 * 2 * .pi + 0.3
                let pc = CGPoint(x: fl.x + cos(a) * 0.035, y: fl.y + sin(a) * 0.035)
                let pts = InkCanvas.ellipsePoints(center: pc, rx: 0.028, ry: 0.028, count: 8)
                _ = c.mass(pts, paint: .paper)
                c.brushLoop(pts, width: pen * 0.7)
            }
            c.circle(fl, 0.018, fill: .ink, width: 0, count: 8)
        case 7: // a pencil behind the ear
            let a = CGPoint(x: f.earL.x - 0.1, y: f.earL.y + 0.07), b = CGPoint(x: f.earL.x + 0.13, y: f.earL.y + 0.15)
            c.brush([a, b], width: 0.032, start: 1, end: 1, swell: 0.01)
            c.brush([a, b], width: 0.02, start: 1, end: 1, swell: 0.01, paint: .light)
            let tip = CGPoint(x: b.x + (b.x - a.x) * 0.18, y: b.y + (b.y - a.y) * 0.18)
            c.brush([b, tip], width: 0.026, start: 1, end: 0.1, swell: 0.01)
        case 9: // sweatband, over the hair
            let top = s.arc(from: .pi + 0.08, to: -0.08, k: 1.08, ky: 1.0, cy: -0.36, n: 10)
            let bottom = s.arc(from: -0.12, to: .pi + 0.12, k: 1.06, ky: 1.0, cy: -0.6, n: 10)
            let band = top + bottom
            _ = c.mass(band, paint: .paper)
            c.clipped(to: c.path(band, closed: true)) { c in
                c.brush(s.arc(from: .pi + 0.1, to: -0.1, k: 1.07, ky: 1.0, cy: -0.48, n: 10), width: 0.014, start: 1, end: 1)
            }
            c.brushLoop(band, width: pen * 0.9)
        case 11: // a nose pin and ear studs
            let pin = CGPoint(x: f.nose.x - 0.012, y: f.nose.y - 0.012)
            c.circle(pin, 0.013, fill: .paper, width: 0, count: 8)
            c.brushLoop(InkCanvas.ellipsePoints(center: pin, rx: 0.013, ry: 0.013, count: 8), width: pen * 0.7)
            c.dot(CGPoint(x: pin.x + 0.003, y: pin.y + 0.003), 0.005)
            if !coveredEars {
                for (dx, dy) in [(-0.012, -0.06), (-0.035, 0.02), (-0.03, 0.045)] as [(CGFloat, CGFloat)] {
                    let p = CGPoint(x: f.earL.x + dx, y: f.earL.y + dy)
                    c.circle(p, 0.011, fill: .ink, width: 0, count: 7)
                    c.dot(CGPoint(x: p.x + 0.003, y: p.y + 0.003), 0.0035)
                }
            }
        case 10: // bubblegum
            let p = CGPoint(x: f.mouth.x + 0.05, y: f.mouth.y - 0.005)
            let pts = InkCanvas.ellipsePoints(center: p, rx: 0.08, ry: 0.075, count: 12)
            _ = c.mass(pts, paint: .paper)
            c.brushLoop(pts, width: pen)
            c.brush([CGPoint(x: p.x - 0.04, y: p.y + 0.04), CGPoint(x: p.x - 0.02, y: p.y + 0.055)], width: pen * 0.7,
                    start: 0.4, end: 0.2)
        default: break
        }
    }

    // MARK: Outfits (body sprite, legs, portrait shoulders)

    private static var oline: CGFloat { CharacterArt.line }

    static func shirtPaint(_ outfit: Int) -> InkPaint {
        switch outfit {
        case 0, 6, 8: return .ink
        case 2: return .medium
        case 5: return .light
        case 9: return .light
        case 11: return .dense
        case tigerFur: return TigerArt.fur
        case 12: return .light // rain jacket
        case 14, 16, 17: return .ink // dark shirt, embroidered top, muscle tank
        case 15: return .medium // fleece
        default: return .paper
        }
    }

    /// Pattern on top of the shirt fill (stripes, overall bib, collar...).
    static func drawOutfitDetail(_ c: inout InkCanvas, _ outfit: Int, torso: CGPath, top: CGFloat, bottom: CGFloat,
                                 halfWidth: CGFloat) {
        switch outfit {
        case 1: // stripes
            c.clipped(to: torso) { c in
                var y = bottom + 0.06
                while y < top {
                    c.fill(c.polygon([CGPoint(x: -halfWidth, y: y), CGPoint(x: halfWidth, y: y + 0.01),
                                      CGPoint(x: halfWidth, y: y + 0.075), CGPoint(x: -halfWidth, y: y + 0.065)], wobble: 0.004), .ink)
                    y += 0.15
                }
            }
        case 3: // white tee with a little V neck
            c.line([CGPoint(x: -0.05, y: top - 0.02), CGPoint(x: 0.0, y: top - 0.1), CGPoint(x: 0.05, y: top - 0.02)],
                   width: oline * 0.8)
        case 4: // overalls: dotted bib and straps over a white shirt
            c.clipped(to: torso) { c in
                c.fillStroke(c.polygon([CGPoint(x: -0.15, y: bottom - 0.1), CGPoint(x: -0.13, y: top - 0.24),
                                        CGPoint(x: 0.13, y: top - 0.24), CGPoint(x: 0.15, y: bottom - 0.1)], wobble: 0.004),
                             fill: .dense, width: oline * 0.8)
                c.line([CGPoint(x: -0.12, y: top - 0.24), CGPoint(x: -0.16, y: top + 0.05)], width: oline * 1.6)
                c.line([CGPoint(x: 0.12, y: top - 0.24), CGPoint(x: 0.16, y: top + 0.05)], width: oline * 1.6)
            }
        case 5: // hoodie: hood behind the neck, drawstrings, pouch pocket
            c.clipped(to: torso) { c in
                c.blob([CGPoint(x: -0.2, y: top + 0.02), CGPoint(x: -0.12, y: top - 0.1), CGPoint(x: 0.12, y: top - 0.1),
                        CGPoint(x: 0.2, y: top + 0.02)], fill: .medium, width: oline)
                c.line([CGPoint(x: -0.05, y: top - 0.09), CGPoint(x: -0.06, y: top - 0.28)], width: oline * 0.6)
                c.line([CGPoint(x: 0.05, y: top - 0.09), CGPoint(x: 0.07, y: top - 0.26)], width: oline * 0.6)
                c.fillStroke(c.polygon([CGPoint(x: -0.15, y: bottom + 0.06), CGPoint(x: -0.11, y: bottom + 0.24),
                                        CGPoint(x: 0.11, y: bottom + 0.24), CGPoint(x: 0.15, y: bottom + 0.06)], wobble: 0.003),
                             fill: nil, width: oline * 0.7)
            }
        case 6: // suit: white shirt, tie, lapels
            c.clipped(to: torso) { c in
                c.fill(c.polygon([CGPoint(x: -0.1, y: top + 0.02), CGPoint(x: 0.1, y: top + 0.02), CGPoint(x: 0.0, y: top - 0.32)],
                                 wobble: 0.003), .paper)
                c.fillStroke(c.polygon([CGPoint(x: -0.025, y: top - 0.04), CGPoint(x: 0.025, y: top - 0.04),
                                        CGPoint(x: 0.035, y: top - 0.24), CGPoint(x: 0.0, y: top - 0.3),
                                        CGPoint(x: -0.035, y: top - 0.24)], wobble: 0.002), fill: .medium, width: oline * 0.6)
                c.line([CGPoint(x: -0.1, y: top + 0.02), CGPoint(x: -0.03, y: top - 0.2), CGPoint(x: 0.0, y: top - 0.33)],
                       width: oline * 0.6, paint: .paper)
                c.line([CGPoint(x: 0.1, y: top + 0.02), CGPoint(x: 0.03, y: top - 0.2), CGPoint(x: 0.0, y: top - 0.33)],
                       width: oline * 0.6, paint: .paper)
                c.circle(CGPoint(x: 0.03, y: top - 0.42), 0.014, fill: .paper, width: 0, count: 6)
            }
        case 7: // hawaiian: open collar and flowers
            c.clipped(to: torso) { c in
                var k = 0
                var y = bottom + 0.08
                while y < top + 0.05 {
                    var x = -halfWidth + (k % 2 == 0 ? 0.05 : 0.14)
                    while x < halfWidth {
                        for p in 0..<5 {
                            let a = CGFloat(p) / 5 * 2 * .pi
                            c.dot(CGPoint(x: x + cos(a) * 0.028, y: y + sin(a) * 0.028), 0.018)
                        }
                        c.circle(CGPoint(x: x, y: y), 0.012, fill: .paper, width: 0, count: 6)
                        x += 0.18
                    }
                    y += 0.16
                    k += 1
                }
                c.fill(c.polygon([CGPoint(x: -0.09, y: top + 0.02), CGPoint(x: 0.09, y: top + 0.02), CGPoint(x: 0.0, y: top - 0.14)],
                                 wobble: 0.002), .paper)
            }
            c.line([CGPoint(x: -0.12, y: top - 0.0), CGPoint(x: -0.02, y: top - 0.16), CGPoint(x: -0.06, y: top - 0.04)],
                   width: oline * 0.7)
            c.line([CGPoint(x: 0.12, y: top - 0.0), CGPoint(x: 0.02, y: top - 0.16), CGPoint(x: 0.06, y: top - 0.04)],
                   width: oline * 0.7)
        case 8: // turtleneck: a rolled collar
            c.clipped(to: torso) { c in
                for k in 0..<2 {
                    let y = top - 0.04 - CGFloat(k) * 0.05
                    c.line([CGPoint(x: -0.1, y: y), CGPoint(x: 0.0, y: y - 0.015), CGPoint(x: 0.1, y: y)],
                           width: oline * 0.6, paint: .paper)
                }
                for x in stride(from: -halfWidth + 0.04, to: halfWidth, by: 0.07) {
                    c.line([CGPoint(x: x, y: bottom + 0.02), CGPoint(x: x, y: bottom + 0.08)], width: oline * 0.4, paint: .paper)
                }
            }
        case 9: // flannel: checks
            c.clipped(to: torso) { c in
                var x = -halfWidth
                while x < halfWidth {
                    c.fill(c.polygon([CGPoint(x: x, y: bottom - 0.2), CGPoint(x: x + 0.06, y: bottom - 0.2),
                                      CGPoint(x: x + 0.06, y: top + 0.2), CGPoint(x: x, y: top + 0.2)], wobble: 0.003), .dense)
                    x += 0.16
                }
                var y = bottom
                while y < top + 0.1 {
                    c.fill(c.polygon([CGPoint(x: -halfWidth, y: y), CGPoint(x: halfWidth, y: y),
                                      CGPoint(x: halfWidth, y: y + 0.06), CGPoint(x: -halfWidth, y: y + 0.06)], wobble: 0.003), .dense)
                    var xi = -halfWidth
                    while xi < halfWidth {
                        c.fill(c.polygon([CGPoint(x: xi, y: y), CGPoint(x: xi + 0.06, y: y),
                                          CGPoint(x: xi + 0.06, y: y + 0.06), CGPoint(x: xi, y: y + 0.06)], wobble: 0.002), .ink)
                        xi += 0.16
                    }
                    y += 0.16
                }
            }
            c.line([CGPoint(x: -0.08, y: top - 0.0), CGPoint(x: 0.0, y: top - 0.1), CGPoint(x: 0.08, y: top - 0.0)],
                   width: oline * 0.8)
        case 10: // tank top: scoop neck and deep armholes
            c.clipped(to: torso) { c in
                c.line(InkCanvas.ellipsePoints(center: CGPoint(x: 0, y: top), rx: 0.1, ry: 0.1, count: 8, from: .pi, to: 2 * .pi),
                       width: oline * 0.8)
                for d in [-1.0, 1.0] as [CGFloat] {
                    c.blob([CGPoint(x: d * (halfWidth + 0.05), y: top + 0.05), CGPoint(x: d * 0.16, y: top + 0.02),
                            CGPoint(x: d * 0.15, y: top - 0.2), CGPoint(x: d * (halfWidth + 0.05), y: top - 0.28)],
                           fill: .light, width: oline * 0.8)
                }
                c.line([CGPoint(x: -0.06, y: bottom + 0.3), CGPoint(x: 0.06, y: bottom + 0.3)], width: oline * 2, paint: .ink)
            }
        case 11: // a long striped scarf over a dotted coat
            c.clipped(to: torso) { c in
                c.fillStroke(c.polygon([CGPoint(x: -0.17, y: top + 0.02), CGPoint(x: 0.17, y: top + 0.02),
                                        CGPoint(x: 0.15, y: top - 0.1), CGPoint(x: -0.15, y: top - 0.1)], wobble: 0.003),
                             fill: .paper, width: oline * 0.8)
            }
            let tail = c.polygon([CGPoint(x: 0.04, y: top - 0.08), CGPoint(x: 0.13, y: top - 0.08),
                                  CGPoint(x: 0.12, y: bottom + 0.12), CGPoint(x: 0.03, y: bottom + 0.14)], wobble: 0.003)
            c.fill(tail, .paper)
            c.clipped(to: tail) { c in
                var y = bottom + 0.16
                while y < top - 0.1 {
                    c.fill(c.polygon([CGPoint(x: 0, y: y), CGPoint(x: 0.2, y: y), CGPoint(x: 0.2, y: y + 0.04),
                                      CGPoint(x: 0, y: y + 0.04)], wobble: 0.002), .ink)
                    y += 0.09
                }
            }
            c.stroke(tail, width: oline * 0.8)
            for k in 0..<4 {
                let x = 0.04 + CGFloat(k) * 0.027
                c.line([CGPoint(x: x, y: bottom + 0.13), CGPoint(x: x, y: bottom + 0.08)], width: oline * 0.5)
            }
        case 12: // rain jacket: hood bunched at the neck, a zip down the front
            c.clipped(to: torso) { c in
                c.blob([CGPoint(x: -0.2, y: top + 0.03), CGPoint(x: -0.13, y: top - 0.08), CGPoint(x: 0.13, y: top - 0.08),
                        CGPoint(x: 0.2, y: top + 0.03)], fill: .dense, width: oline)
                c.line([CGPoint(x: 0.0, y: top - 0.08), CGPoint(x: 0.005, y: bottom - 0.1)], width: oline * 0.9)
                var y = top - 0.12
                while y > bottom {
                    c.line([CGPoint(x: -0.018, y: y), CGPoint(x: 0.022, y: y)], width: oline * 0.4)
                    y -= 0.045
                }
                c.fillStroke(c.polygon([CGPoint(x: 0.09, y: top - 0.2), CGPoint(x: 0.16, y: top - 0.2),
                                        CGPoint(x: 0.16, y: top - 0.25), CGPoint(x: 0.09, y: top - 0.25)], wobble: 0.002),
                             fill: .paper, width: oline * 0.5)
            }
        case 13, 14: // a collared shirt (white or dark)
            let edge: InkPaint = outfit == 13 ? .ink : .paper
            c.clipped(to: torso) { c in
                for d in [-1.0, 1.0] as [CGFloat] {
                    let collar = c.polygon([CGPoint(x: 0.0, y: top - 0.1), CGPoint(x: d * 0.12, y: top + 0.03),
                                            CGPoint(x: d * 0.15, y: top - 0.04), CGPoint(x: d * 0.05, y: top - 0.15)], wobble: 0.002)
                    c.fill(collar, outfit == 13 ? .paper : .ink)
                    c.stroke(collar, width: oline * 0.7, paint: edge)
                }
                c.line([CGPoint(x: 0.0, y: top - 0.12), CGPoint(x: 0.005, y: bottom - 0.1)], width: oline * 0.5, paint: edge)
                var y = top - 0.2
                while y > bottom {
                    c.circle(CGPoint(x: 0.025, y: y), 0.011, fill: edge, width: 0, count: 6)
                    y -= 0.13
                }
            }
        case 15: // fleece jacket open over a ringer tee
            c.clipped(to: torso) { c in
                c.fill(c.polygon([CGPoint(x: -0.09, y: top + 0.05), CGPoint(x: 0.09, y: top + 0.05),
                                  CGPoint(x: 0.07, y: bottom - 0.2), CGPoint(x: -0.07, y: bottom - 0.2)], wobble: 0.003), .paper)
                c.line(InkCanvas.ellipsePoints(center: CGPoint(x: 0, y: top + 0.01), rx: 0.08, ry: 0.06, count: 8, from: .pi, to: 2 * .pi),
                       width: oline * 1.3)
                c.line([CGPoint(x: -0.09, y: top + 0.02), CGPoint(x: -0.07, y: bottom - 0.15)], width: oline * 0.7)
                c.line([CGPoint(x: 0.09, y: top + 0.02), CGPoint(x: 0.07, y: bottom - 0.15)], width: oline * 0.7)
            }
        case 16: // dark top with white embroidery on one side
            c.clipped(to: torso) { c in
                for (x, y, r) in [(0.13, top - 0.2, 0.05), (0.18, top - 0.33, 0.035), (0.08, top - 0.32, 0.03)] as [(CGFloat, CGFloat, CGFloat)] {
                    for k in 0..<6 {
                        let a = CGFloat(k) / 6 * 2 * .pi
                        c.circle(CGPoint(x: x + cos(a) * r, y: y + sin(a) * r), r * 0.32, fill: nil, width: oline * 0.35, count: 6)
                    }
                    c.circle(CGPoint(x: x, y: y), r * 0.3, fill: .paper, width: 0, count: 6)
                }
            }
            c.line(InkCanvas.ellipsePoints(center: CGPoint(x: 0, y: top), rx: 0.09, ry: 0.07, count: 8, from: .pi, to: 2 * .pi),
                   width: oline * 0.5, paint: .paper)
        case 17: // muscle tank and a thick curb chain
            c.clipped(to: torso) { c in
                for d in [-1.0, 1.0] as [CGFloat] {
                    // Big shoulders and arms out of the armholes.
                    c.blob([CGPoint(x: d * (halfWidth + 0.06), y: top + 0.06), CGPoint(x: d * 0.15, y: top + 0.04),
                            CGPoint(x: d * 0.13, y: top - 0.24), CGPoint(x: d * (halfWidth + 0.06), y: top - 0.34)],
                           fill: .medium, width: oline * 0.8)
                    c.line([CGPoint(x: d * 0.2, y: top - 0.04), CGPoint(x: d * 0.25, y: top - 0.16)], width: oline * 0.5)
                }
                c.line(InkCanvas.ellipsePoints(center: CGPoint(x: 0, y: top + 0.02), rx: 0.12, ry: 0.13, count: 8, from: .pi, to: 2 * .pi),
                       width: oline * 0.8)
            }
            // The chain: chunky interlocking links.
            for k in 0..<11 {
                let t = CGFloat.pi * (1.12 + 0.76 * CGFloat(k) / 10)
                let p = CGPoint(x: cos(t) * 0.13, y: top + 0.0 + sin(t) * 0.15)
                c.ellipse(p, 0.024, 0.017, fill: .paper, width: oline * 0.75)
                c.ellipse(p, 0.008, 0.006, fill: .ink, width: 0)
            }
        case tigerFur: // tabby stripes and a pale belly
            c.clipped(to: torso) { c in
                c.ellipse(CGPoint(x: 0.04, y: (top + bottom) / 2 - 0.04), 0.13, (top - bottom) * 0.38, fill: .paper, width: 0)
                for k in 0..<4 {
                    let y = bottom + 0.12 + CGFloat(k) * 0.13
                    c.line([CGPoint(x: -halfWidth - 0.02, y: y + 0.02), CGPoint(x: -halfWidth + 0.12, y: y),
                            CGPoint(x: -halfWidth + 0.17, y: y - 0.03)], width: oline * 1.3)
                    c.line([CGPoint(x: halfWidth + 0.02, y: y + 0.02), CGPoint(x: halfWidth - 0.1, y: y),
                            CGPoint(x: halfWidth - 0.14, y: y - 0.03)], width: oline * 1.3)
                }
            }
        default: break
        }
    }

    static func trousers(_ outfit: Int) -> InkPaint {
        switch outfit {
        case 0, 4: return .dense
        case 7, 10: return .medium
        case tigerFur: return TigerArt.fur
        default: return .ink
        }
    }

    static func shoes(_ outfit: Int) -> InkPaint { outfit == 0 || outfit == 6 ? .ink : .paper }
}

/// Tiger, the tabby cat (an easter egg in "Start from"). Same head space and
/// expressions as everyone else, inked the same way.
enum TigerArt {
    /// A dark brown tabby coat.
    static let fur = InkPaint.dots(0.6)

    private static let pen = AvatarArt.pen

    /// Modelled on the real Tiger: a brown tabby with dark stripes fanning up
    /// the forehead, heavy-lidded and thoroughly unimpressed, dark "eyeliner"
    /// streaks from the eye corners, a pale muzzle, white whiskers and big ears.
    static func drawHead(_ c: inout InkCanvas, _ expr: Expression) {
        let h = CharacterArt.headCenter
        let rx: CGFloat = 0.27, ry: CGFloat = 0.225
        let cy = h.y - 0.02
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: h.x + x, y: cy + y) }

        // Big ears, pale and tufted inside.
        for (x, lean) in [(-0.15, -0.06), (0.16, 0.05)] as [(CGFloat, CGFloat)] {
            let base = P(x, ry * 0.6)
            let ear = [CGPoint(x: base.x - 0.11, y: base.y - 0.04), CGPoint(x: base.x + lean, y: base.y + 0.22),
                       CGPoint(x: base.x + 0.105, y: base.y - 0.04)]
            _ = c.mass(ear, paint: TigerArt.fur, angular: true)
            _ = c.mass([CGPoint(x: base.x - 0.055, y: base.y - 0.01), CGPoint(x: base.x + lean * 0.85, y: base.y + 0.15),
                        CGPoint(x: base.x + 0.05, y: base.y - 0.01)], paint: .paper, angular: true)
            for k in 0..<3 {
                let t = CGFloat(k) * 0.03 - 0.03
                c.brush([CGPoint(x: base.x + t, y: base.y), CGPoint(x: base.x + t * 0.6 + lean * 0.4, y: base.y + 0.09)],
                        width: pen * 0.35, start: 0.6, end: 0.1)
            }
            c.brushLoop(ear, width: AvatarArt.line, angular: true)
        }

        // A broad, fluffy head: tufts at the cheeks.
        var pts: [CGPoint] = []
        for k in 0..<28 {
            let t = CGFloat(k) / 28 * 2 * .pi
            let tuft: CGFloat = (abs(cos(t)) > 0.7 && sin(t) < 0.3) ? (k % 2 == 0 ? 1.1 : 0.97) : 1
            pts.append(P(cos(t) * rx * tuft, sin(t) * ry * tuft))
        }
        let dense = InkCanvas.smoothed(pts, closed: true, perSegment: 4)
        let head = CGMutablePath()
        head.addLines(between: dense)
        head.closeSubpath()
        c.fill(head, TigerArt.fur)
        let e1 = P(-0.085, 0.01), e2 = P(0.09, 0.012)
        c.clipped(to: head) { c in
            // Pale muzzle and chin, pale patches above the eyes.
            _ = c.mass([P(-0.12, -0.04), P(-0.05, 0.0), P(0.0, -0.01), P(0.05, 0.0), P(0.12, -0.04), P(0.13, -0.15),
                        P(0.0, -0.24), P(-0.13, -0.15)], paint: .paper)
            for e in [e1, e2] { c.ellipse(CGPoint(x: e.x, y: e.y + 0.055), 0.05, 0.022, fill: .light, width: 0) }
            // Forehead stripes: fanning up from between the eyes.
            for (x0, lean, len, w) in [(-0.01, -0.01, 0.2, 1.7), (0.025, 0.012, 0.21, 1.7), (-0.05, -0.05, 0.16, 1.4),
                                       (0.065, 0.055, 0.16, 1.4), (-0.095, -0.09, 0.12, 1.2), (0.11, 0.09, 0.12, 1.2)]
                as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                c.brush([P(x0, 0.07), P(x0 + lean * 0.4, 0.07 + len * 0.5), P(x0 + lean, 0.07 + len)],
                        width: pen * w, start: 0.9, end: 0.1, swell: 0.15)
            }
            // Eyeliner streaks from the outer corners, and cheek stripes.
            c.brush([P(-0.13, 0.0), P(-0.19, -0.025), P(-0.25, -0.02)], width: pen * 1.5, start: 1, end: 0.1)
            c.brush([P(0.135, 0.004), P(0.195, -0.02), P(0.255, -0.015)], width: pen * 1.5, start: 1, end: 0.1)
            for d in [-1.0, 1.0] as [CGFloat] {
                c.brush([P(d * 0.28, -0.07), P(d * 0.2, -0.08), P(d * 0.15, -0.065)], width: pen * 1.4, start: 0.9, end: 0.1)
                c.brush([P(d * 0.28, -0.12), P(d * 0.21, -0.13)], width: pen * 1.2, start: 0.9, end: 0.1)
            }
            // White whiskers over the fur.
            for k in 0..<3 {
                let dy = CGFloat(k - 1) * 0.018
                c.brush([P(0.06, -0.1 + dy), P(0.3, -0.08 + dy * 2.5)], width: pen * 0.4, start: 0.8, end: 0.2, paint: .paper)
                c.brush([P(-0.06, -0.1 + dy), P(-0.3, -0.08 + dy * 2.5)], width: pen * 0.4, start: 0.8, end: 0.2, paint: .paper)
            }
        }
        c.brushLoop(pts, width: AvatarArt.line)
        // Whiskers carry on past the cheeks in ink.
        for k in 0..<3 {
            let dy = CGFloat(k - 1) * 0.018
            c.brush([P(0.28, -0.08 + dy * 2.4), P(0.36, -0.07 + dy * 3)], width: pen * 0.35, start: 0.6, end: 0.1)
            c.brush([P(-0.28, -0.08 + dy * 2.4), P(-0.36, -0.07 + dy * 3)], width: pen * 0.35, start: 0.6, end: 0.1)
        }

        switch expr {
        case .hit, .defeated, .focused, .blink, .victorious:
            AvatarArt.expressionEyes(&c, e1, e2, expr)
        default: // almond eyes, pale irises, big pupils, heavy unimpressed lids
            for (i, e) in [e1, e2].enumerated() {
                let d: CGFloat = i == 0 ? -1 : 1
                let eye = [CGPoint(x: e.x - d * 0.05, y: e.y - 0.004), CGPoint(x: e.x, y: e.y + 0.026),
                           CGPoint(x: e.x + d * 0.052, y: e.y + 0.012), CGPoint(x: e.x + d * 0.01, y: e.y - 0.026)]
                let eyePath = c.mass(eye, paint: .light)
                c.clipped(to: eyePath) { c in
                    c.ellipse(CGPoint(x: e.x + 0.006, y: e.y - 0.004), 0.019, 0.021, fill: .ink, width: 0)
                    // The lid: low and flat. Not impressed.
                    _ = c.mass([CGPoint(x: e.x - 0.07, y: e.y + 0.05), CGPoint(x: e.x + 0.07, y: e.y + 0.05),
                                CGPoint(x: e.x + 0.07, y: e.y + 0.008 - d * 0.004), CGPoint(x: e.x - 0.07, y: e.y + 0.006 + d * 0.004)],
                               paint: TigerArt.fur)
                }
                c.brushLoop(eye, width: pen * 1.1)
                c.brush([CGPoint(x: e.x - 0.048, y: e.y + 0.006 + d * 0.004), CGPoint(x: e.x + 0.05, y: e.y + 0.008 - d * 0.004)],
                        width: pen * 1.4, start: 0.6, end: 0.6)
            }
        }
        // Nose: pale, outlined, with a line down to the mouth.
        let n = P(0.0, -0.06)
        let nose = [CGPoint(x: n.x - 0.026, y: n.y + 0.012), CGPoint(x: n.x + 0.026, y: n.y + 0.012), CGPoint(x: n.x, y: n.y - 0.018)]
        _ = c.mass(nose, paint: .light, angular: true)
        c.brushLoop(nose, width: pen * 0.8, angular: true)
        c.brush([CGPoint(x: n.x, y: n.y - 0.018), CGPoint(x: n.x, y: n.y - 0.04)], width: pen * 0.7, start: 0.6, end: 0.6)
        switch expr {
        case .hit, .victorious:
            c.ellipse(CGPoint(x: n.x, y: n.y - 0.07), 0.028, 0.026, fill: .ink, width: 0)
        default: // a small, flat, judging mouth
            c.brush([CGPoint(x: n.x - 0.04, y: n.y - 0.05), CGPoint(x: n.x - 0.018, y: n.y - 0.042), CGPoint(x: n.x, y: n.y - 0.04),
                     CGPoint(x: n.x + 0.018, y: n.y - 0.042), CGPoint(x: n.x + 0.04, y: n.y - 0.05)], width: pen * 0.9,
                    start: 0.3, end: 0.3)
        }
        if expr == .relieved { CharacterArt.sweat(&c, CGPoint(x: h.x - rx - 0.05, y: h.y + 0.1)) }
    }

    /// A curling tabby tail, drawn behind the legs.
    static func drawTail(_ c: inout InkCanvas) {
        let pts = [CGPoint(x: -0.12, y: 0.86), CGPoint(x: -0.3, y: 0.7), CGPoint(x: -0.44, y: 0.82),
                   CGPoint(x: -0.42, y: 1.02), CGPoint(x: -0.34, y: 1.08)]
        c.brush(pts, width: 0.095, start: 0.9, end: 0.5, swell: 0.1)
        c.brush(pts, width: 0.062, start: 0.85, end: 0.4, swell: 0.1, paint: TigerArt.fur)
        for p in [CGPoint(x: -0.3, y: 0.71), CGPoint(x: -0.43, y: 0.86), CGPoint(x: -0.4, y: 1.02)] {
            c.dot(p, 0.026)
        }
    }
}
