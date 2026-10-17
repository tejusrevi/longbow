import CoreGraphics
import LongbowCore

/// The chicken: a dim, googly-eyed, tongue-out side character who wanders
/// about where arrows land. Drawn in metres, feet at the origin, facing right.
enum ChickenArt {
    enum Pose: String, CaseIterable {
        case stand, peck, step, panic, dead
    }

    static let line: CGFloat = 0.02
    static let bounds = CGRect(x: -0.34, y: -0.04, width: 0.88, height: 0.9)
    /// Rough body box for arrow hits, relative to the feet.
    static let hitBox = CGRect(x: -0.22, y: 0.0, width: 0.42, height: 0.62)

    static func draw(_ c: inout InkCanvas, _ pose: Pose) {
        if pose == .dead { return drawDead(&c) }
        drawLegs(&c, stepping: pose == .step || pose == .panic)

        // Body with a perky tail; halftone on the underside.
        let body = c.path([
            CGPoint(x: -0.15, y: 0.17), CGPoint(x: -0.1, y: 0.12), CGPoint(x: 0.02, y: 0.11), CGPoint(x: 0.12, y: 0.14),
            CGPoint(x: 0.16, y: 0.22), CGPoint(x: 0.12, y: 0.3), CGPoint(x: 0.02, y: 0.33), CGPoint(x: -0.1, y: 0.32),
            CGPoint(x: -0.18, y: 0.31), CGPoint(x: -0.25, y: 0.42), CGPoint(x: -0.27, y: 0.34), CGPoint(x: -0.21, y: 0.24),
        ], closed: true)
        c.fill(body, .paper)
        c.clipped(to: body) { c in
            c.fill(c.polygon([CGPoint(x: -0.4, y: 0.0), CGPoint(x: 0.3, y: 0.0), CGPoint(x: 0.3, y: 0.2),
                              CGPoint(x: -0.4, y: 0.23)], wobble: 0.004), .medium)
            c.fill(c.polygon([CGPoint(x: -0.4, y: 0.23), CGPoint(x: 0.3, y: 0.2), CGPoint(x: 0.3, y: 0.24),
                              CGPoint(x: -0.4, y: 0.27)], wobble: 0.004), .light)
        }
        c.stroke(body, width: line)

        // Wing: folded, or flapping in a panic.
        if pose == .panic {
            c.blob([CGPoint(x: -0.1, y: 0.29), CGPoint(x: -0.2, y: 0.5), CGPoint(x: -0.13, y: 0.47),
                    CGPoint(x: -0.08, y: 0.54), CGPoint(x: -0.02, y: 0.47), CGPoint(x: 0.03, y: 0.3)], fill: .dense, width: line)
        } else {
            c.blob([CGPoint(x: -0.13, y: 0.29), CGPoint(x: -0.02, y: 0.3), CGPoint(x: 0.06, y: 0.27),
                    CGPoint(x: 0.02, y: 0.21), CGPoint(x: -0.04, y: 0.18), CGPoint(x: -0.09, y: 0.2),
                    CGPoint(x: -0.14, y: 0.23)], fill: .dense, width: line)
        }

        // Neck and head; pecking swings them down to the ground.
        c.ctx.saveGState()
        if pose == .peck {
            c.ctx.translateBy(x: 0.08, y: 0.28)
            c.ctx.rotate(by: -1.15)
            c.ctx.translateBy(x: -0.08, y: -0.28)
        }
        drawHead(&c, alarmed: pose == .panic)
        c.ctx.restoreGState()
    }

    private static func drawLegs(_ c: inout InkCanvas, stepping: Bool) {
        let legs: [(CGPoint, CGPoint)] = stepping
            ? [(CGPoint(x: -0.03, y: 0.13), CGPoint(x: -0.06, y: 0.01)), (CGPoint(x: 0.05, y: 0.13), CGPoint(x: 0.13, y: 0.07))]
            : [(CGPoint(x: -0.03, y: 0.13), CGPoint(x: -0.04, y: 0.01)), (CGPoint(x: 0.05, y: 0.13), CGPoint(x: 0.06, y: 0.01))]
        for (top, foot) in legs {
            c.line([top, foot], width: line * 0.9)
            for a in [-0.35, 0.0, 0.35] as [CGFloat] {
                c.line([foot, CGPoint(x: foot.x + cos(a) * 0.05, y: foot.y + sin(a) * 0.02 - 0.005)], width: line * 0.8)
            }
        }
    }

    private static func drawHead(_ c: inout InkCanvas, alarmed: Bool) {
        c.blob([CGPoint(x: 0.05, y: 0.29), CGPoint(x: 0.13, y: 0.26), CGPoint(x: 0.15, y: 0.4), CGPoint(x: 0.18, y: 0.52),
                CGPoint(x: 0.15, y: 0.6), CGPoint(x: 0.08, y: 0.62), CGPoint(x: 0.03, y: 0.57), CGPoint(x: 0.05, y: 0.45)],
               fill: .paper, width: line)
        // Comb.
        for (x, y) in [(0.065, 0.635), (0.1, 0.655), (0.135, 0.635)] as [(CGFloat, CGFloat)] {
            c.circle(CGPoint(x: x, y: y), 0.024, fill: .ink, width: 0, count: 8)
        }
        // Beak, open, tongue out.
        c.blob([CGPoint(x: 0.17, y: 0.555), CGPoint(x: 0.3, y: 0.535), CGPoint(x: 0.17, y: 0.515)], fill: .paper, width: line * 0.9)
        let drop: CGFloat = alarmed ? 0.03 : 0
        c.blob([CGPoint(x: 0.17, y: 0.5), CGPoint(x: 0.26, y: 0.47 - drop), CGPoint(x: 0.165, y: 0.47 - drop * 0.5)],
               fill: .paper, width: line * 0.9)
        c.blob([CGPoint(x: 0.19, y: 0.505), CGPoint(x: 0.25, y: 0.495), CGPoint(x: 0.285, y: 0.465 - drop),
                CGPoint(x: 0.24, y: 0.47 - drop), CGPoint(x: 0.19, y: 0.49)], fill: .light, width: line * 0.7)
        // Wattle.
        c.blob([CGPoint(x: 0.165, y: 0.49), CGPoint(x: 0.17, y: 0.43), CGPoint(x: 0.14, y: 0.45)], fill: .ink, width: 0)
        // Googly eyes, pupils pointing different ways.
        let r: CGFloat = alarmed ? 0.042 : 0.036
        c.circle(CGPoint(x: 0.09, y: 0.57), r, fill: .paper, width: line * 0.9, count: 10)
        c.circle(CGPoint(x: 0.145, y: 0.578), r, fill: .paper, width: line * 0.9, count: 10)
        c.dot(CGPoint(x: 0.078, y: 0.562), alarmed ? 0.009 : 0.013)
        c.dot(CGPoint(x: 0.16, y: 0.59), alarmed ? 0.009 : 0.013)
        if alarmed {
            for (a, len) in [(1.25, 0.07), (1.6, 0.08), (1.95, 0.07)] as [(CGFloat, CGFloat)] {
                let o = CGPoint(x: 0.11 + cos(a) * 0.12, y: 0.62 + sin(a) * 0.12)
                c.line([o, CGPoint(x: o.x + cos(a) * len, y: o.y + sin(a) * len)], width: line)
            }
        }
    }

    /// Flat on its back, feet in the air, X eyes, tongue out.
    private static func drawDead(_ c: inout InkCanvas) {
        // Legs up, toes curled.
        for (base, tip) in [(CGPoint(x: -0.04, y: 0.19), CGPoint(x: -0.07, y: 0.36)),
                            (CGPoint(x: 0.05, y: 0.19), CGPoint(x: 0.08, y: 0.37))] {
            c.line([base, tip], width: line * 0.9)
            for a in [0.9, 1.57, 2.2] as [CGFloat] {
                c.line([tip, CGPoint(x: tip.x + cos(a) * 0.04, y: tip.y + sin(a) * 0.035)], width: line * 0.8)
            }
        }
        // Body, belly up.
        let body = c.path([CGPoint(x: -0.2, y: 0.1), CGPoint(x: -0.12, y: 0.2), CGPoint(x: 0.04, y: 0.22),
                           CGPoint(x: 0.15, y: 0.17), CGPoint(x: 0.17, y: 0.08), CGPoint(x: 0.06, y: 0.02),
                           CGPoint(x: -0.1, y: 0.02), CGPoint(x: -0.28, y: 0.0), CGPoint(x: -0.27, y: 0.07)], closed: true)
        c.fill(body, .paper)
        c.clipped(to: body) { c in
            c.fill(c.polygon([CGPoint(x: -0.4, y: 0.16), CGPoint(x: 0.3, y: 0.13), CGPoint(x: 0.3, y: 0.4), CGPoint(x: -0.4, y: 0.4)],
                             wobble: 0.004), .medium)
        }
        c.stroke(body, width: line)
        c.blob([CGPoint(x: -0.12, y: 0.06), CGPoint(x: 0.02, y: 0.04), CGPoint(x: 0.06, y: 0.1), CGPoint(x: -0.06, y: 0.12)],
               fill: .dense, width: line)
        // Neck flopped out to the right, head on the ground.
        c.blob([CGPoint(x: 0.12, y: 0.06), CGPoint(x: 0.26, y: 0.02), CGPoint(x: 0.36, y: 0.03), CGPoint(x: 0.37, y: 0.11),
                CGPoint(x: 0.28, y: 0.13), CGPoint(x: 0.14, y: 0.14)], fill: .paper, width: line)
        for (x, y) in [(0.3, 0.145), (0.335, 0.14)] as [(CGFloat, CGFloat)] {
            c.circle(CGPoint(x: x, y: y), 0.018, fill: .ink, width: 0, count: 7)
        }
        for e in [CGPoint(x: 0.29, y: 0.085), CGPoint(x: 0.335, y: 0.08)] {
            let r: CGFloat = 0.014
            c.line([CGPoint(x: e.x - r, y: e.y - r), CGPoint(x: e.x + r, y: e.y + r)], width: line * 0.8)
            c.line([CGPoint(x: e.x - r, y: e.y + r), CGPoint(x: e.x + r, y: e.y - r)], width: line * 0.8)
        }
        c.blob([CGPoint(x: 0.36, y: 0.08), CGPoint(x: 0.42, y: 0.03), CGPoint(x: 0.355, y: 0.04)], fill: .paper, width: line * 0.8)
        c.blob([CGPoint(x: 0.36, y: 0.04), CGPoint(x: 0.38, y: -0.01), CGPoint(x: 0.4, y: 0.0), CGPoint(x: 0.39, y: 0.03)],
               fill: .light, width: line * 0.6)
    }

    /// A single loose feather, for puffs.
    static let featherBounds = CGRect(x: -0.06, y: -0.03, width: 0.12, height: 0.06)
    static func drawFeather(_ c: inout InkCanvas) {
        c.blob([CGPoint(x: -0.05, y: 0), CGPoint(x: 0, y: 0.022), CGPoint(x: 0.05, y: 0.004), CGPoint(x: 0, y: -0.018)],
               fill: .paper, width: 0.008)
        c.line([CGPoint(x: -0.055, y: -0.002), CGPoint(x: 0.04, y: 0.004)], width: 0.006)
    }

    // MARK: Front view (the splash screen's star)

    static let frontBounds = CGRect(x: -0.4, y: -0.04, width: 0.8, height: 1.2)
    /// Eye centres and radii, for live pupils and lids drawn on top.
    static let frontEyes: [(center: CGPoint, radius: CGFloat)] = [
        (CGPoint(x: -0.072, y: 0.885), 0.08), (CGPoint(x: 0.078, y: 0.895), 0.087),
    ]

    /// Facing you, deadpan. Eyes are left empty: the pupils are drawn live.
    static func drawFront(_ c: inout InkCanvas) {
        let pen: CGFloat = 0.016
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        c.fill(c.path(InkCanvas.ellipsePoints(center: P(0, 0.01), rx: 0.27, ry: 0.028, count: 14), closed: true), .light)

        // Legs and toes.
        for d in [-1.0, 1.0] as [CGFloat] {
            c.brush([P(d * 0.07, 0.13), P(d * 0.075, 0.07), P(d * 0.08, 0.02)], width: pen * 1.1, start: 0.8, end: 0.6)
            for a in [-0.5, 0.0, 0.5] as [CGFloat] {
                let toe = P(d * 0.08 + sin(a) * 0.05, 0.005 - cos(a) * 0.006)
                c.brush([P(d * 0.08, 0.02), toe], width: pen * 0.9, start: 0.8, end: 0.2)
            }
        }

        // Body: a plump egg, halftone belly.
        let body = InkCanvas.ellipsePoints(center: P(0, 0.31), rx: 0.27, ry: 0.235, count: 16)
        let bodyPath = c.mass(body, paint: .paper)
        c.clipped(to: bodyPath) { c in
            c.fill(c.path([P(-0.4, 0.0), P(0.4, 0.0), P(0.4, 0.2), P(0.0, 0.17), P(-0.4, 0.21)], closed: true), .medium)
            c.fill(c.path([P(-0.4, 0.21), P(0.0, 0.17), P(0.4, 0.2), P(0.4, 0.26), P(0.0, 0.23), P(-0.4, 0.27)], closed: true), .light)
        }
        c.brushLoop(body, width: 0.022)

        // Wings, tucked at the sides.
        for d in [-1.0, 1.0] as [CGFloat] {
            // Folded wing with three feather tips at the bottom.
            let wing = [P(d * 0.2, 0.45), P(d * 0.3, 0.41), P(d * 0.345, 0.31), P(d * 0.335, 0.2), P(d * 0.315, 0.13),
                        P(d * 0.29, 0.18), P(d * 0.265, 0.12), P(d * 0.24, 0.18), P(d * 0.215, 0.14), P(d * 0.205, 0.24)]
            _ = c.mass(wing, paint: .dense)
            c.brushLoop(wing, width: pen)
            c.brush([P(d * 0.24, 0.38), P(d * 0.3, 0.3), P(d * 0.31, 0.22)], width: pen * 0.55, start: 0.3, end: 0.1,
                    paint: .paper)
        }

        // Neck and head, one long goofy shape.
        let head = [P(-0.1, 0.46), P(-0.115, 0.66), P(-0.16, 0.8), P(-0.155, 0.96), P(-0.07, 1.04), P(0.07, 1.045),
                    P(0.16, 0.97), P(0.17, 0.81), P(0.125, 0.66), P(0.11, 0.46)]
        _ = c.mass(head, paint: .paper)
        c.brush(Array(head.prefix(6)), width: 0.02, start: 0.4, end: 0.8, swell: 0.2)
        c.brush(Array(head.suffix(5).reversed()), width: 0.02, start: 0.4, end: 0.8, swell: 0.2)
        c.brush([P(-0.07, 1.04), P(0.0, 1.05), P(0.07, 1.045)], width: 0.018, start: 0.8, end: 0.8)
        // A few neck feathers.
        for (x, y) in [(-0.05, 0.6), (0.04, 0.56), (0.0, 0.66)] as [(CGFloat, CGFloat)] {
            c.brush([P(x - 0.015, y + 0.012), P(x, y), P(x + 0.015, y + 0.012)], width: pen * 0.6, start: 0.3, end: 0.3)
        }

        // Comb.
        for (x, y, r) in [(-0.065, 1.07, 0.04), (0.005, 1.1, 0.048), (0.075, 1.07, 0.04)] as [(CGFloat, CGFloat, CGFloat)] {
            _ = c.mass(InkCanvas.ellipsePoints(center: P(x, y), rx: r, ry: r * 0.95, count: 10))
        }

        // Eye whites (pupils are live).
        for (e, r) in frontEyes {
            let pts = InkCanvas.ellipsePoints(center: e, rx: r, ry: r, count: 12)
            _ = c.mass(pts, paint: .paper)
            c.brushLoop(pts, width: pen * 1.05)
        }

        // Beak, seen from the front, a little open; wattle below.
        let upper = [P(-0.045, 0.795), P(0.0, 0.81), P(0.05, 0.795), P(0.012, 0.735)]
        _ = c.mass(upper, paint: .paper)
        c.brushLoop(upper, width: pen)
        c.brush([P(-0.025, 0.74), P(0.005, 0.715), P(0.03, 0.74)], width: pen * 0.9, start: 0.5, end: 0.5)
        c.dot(P(-0.012, 0.79), 0.005)
        c.dot(P(0.02, 0.79), 0.005)
        _ = c.mass([P(0.0, 0.705), P(0.03, 0.68), P(0.02, 0.63), P(-0.008, 0.66)])
    }

    // MARK: Close-up (the splash: a chicken finds the camera)

    static let closeBounds = CGRect(x: -0.5, y: -0.25, width: 1.0, height: 1.25)
    static let closeEyes: [(center: CGPoint, radius: CGFloat)] = [
        (CGPoint(x: -0.125, y: 0.56), 0.14), (CGPoint(x: 0.135, y: 0.565), 0.148),
    ]

    /// A head right up against the lens: a scalloped comb, two enormous eyes
    /// squashed together (pupils live), a pointed beak aimed at you, a
    /// halftone shadow down one side, and the neck out of frame.
    static func drawCloseUp(_ c: inout InkCanvas) {
        let pen: CGFloat = 0.02
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        // Neck.
        let neck = [P(-0.24, -0.4), P(-0.25, 0.0), P(-0.2, 0.2), P(0.22, 0.2), P(0.26, 0.0), P(0.27, -0.4)]
        let neckPath = c.mass(neck, paint: .paper)
        c.clipped(to: neckPath) { c in
            _ = c.mass([P(0.1, 0.25), P(0.4, 0.25), P(0.4, -0.45), P(0.14, -0.45)], paint: .dots(0.12))
        }
        c.brush([P(-0.24, -0.35), P(-0.25, 0.0), P(-0.21, 0.18)], width: 0.024, start: 0.9, end: 0.6)
        c.brush([P(0.27, -0.35), P(0.26, 0.0), P(0.22, 0.18)], width: 0.024, start: 0.9, end: 0.6)

        // Comb: three round lobes, dotted, peeking over the head.
        var comb: [CGPoint] = [P(-0.2, 0.78)]
        for (x, y, r) in [(-0.15, 0.86, 0.075), (-0.02, 0.92, 0.085), (0.11, 0.88, 0.075)] as [(CGFloat, CGFloat, CGFloat)] {
            comb += InkCanvas.ellipsePoints(center: P(x, y), rx: r, ry: r, count: 8, from: .pi * 1.05, to: .pi * -0.05)
        }
        comb += [P(0.18, 0.78)]
        _ = c.mass(comb, paint: .dots(0.18))
        c.brushLoop(comb, width: pen * 1.1)

        // Head: an egg, shaded down the right side.
        let head = InkCanvas.ellipsePoints(center: P(0.0, 0.47), rx: 0.34, ry: 0.37, count: 18)
        let headPath = c.mass(head, paint: .paper)
        c.clipped(to: headPath) { c in
            let shade = CGMutablePath()
            shade.addEllipse(in: CGRect(x: -0.32, y: 0.05, width: 0.8, height: 0.84))
            shade.addEllipse(in: CGRect(x: -0.4, y: 0.16, width: 0.7, height: 0.78))
            c.ctx.addPath(shade)
            c.ctx.setFillColor(InkPaint.dots(0.16).cgColor)
            c.ctx.fillPath(using: .evenOdd)
        }
        c.brushLoop(head, width: 0.03)

        // Eye whites, squashed together (pupils and lids are live).
        for (e, r) in closeEyes {
            let pts = InkCanvas.ellipsePoints(center: e, rx: r, ry: r * 0.94, count: 16)
            _ = c.mass(pts, paint: .paper)
            c.brushLoop(pts, width: pen * 1.15)
        }
        // Beak, pointing down at you, a little crooked.
        let beak = [P(-0.085, 0.405), P(0.0, 0.42), P(0.095, 0.4), P(0.012, 0.25)]
        _ = c.mass(beak, paint: .paper)
        c.brushLoop(beak, width: pen * 1.1)
        c.brush([P(-0.04, 0.39), P(-0.02, 0.385)], width: pen * 0.6, start: 0.7, end: 0.3)
        c.brush([P(0.03, 0.385), P(0.05, 0.39)], width: pen * 0.6, start: 0.7, end: 0.3)
        // Wattle: a little dotted chevron under the beak.
        let wattle = [P(-0.035, 0.235), P(0.012, 0.21), P(0.055, 0.235), P(0.02, 0.13), P(0.0, 0.13)]
        _ = c.mass(wattle, paint: .dots(0.2))
        c.brushLoop(wattle, width: pen * 0.8)
    }

    // MARK: Profile close-up (the splash, take two)

    static let profileBounds = CGRect(x: -0.62, y: -0.3, width: 1.24, height: 1.36)
    static let profileEye: [(center: CGPoint, radius: CGFloat)] = [(CGPoint(x: 0.1, y: 0.5), 0.058)]

    /// A real chicken's head in profile, close enough to fill the lens: one
    /// eye on the camera, serrated comb, hooked beak, wattle and earlobe, and
    /// pointed hackle feathers down the neck. Pupil is live.
    static func drawProfileCloseUp(_ c: inout InkCanvas) {
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        let pen: CGFloat = 0.014

        // Neck, out of the bottom of the frame.
        let neck = [P(-0.3, 0.32), P(-0.36, 0.05), P(-0.44, -0.4), P(0.26, -0.4), P(0.19, -0.05), P(0.13, 0.24)]
        let neckPath = c.mass(neck, paint: .paper)
        c.clipped(to: neckPath) { c in
            // Shade down the back of the neck.
            _ = c.mass([P(-0.5, 0.35), P(-0.22, 0.3), P(-0.2, -0.45), P(-0.6, -0.45)], paint: .light)
            // Hackle feathers: loose, overlapping strokes sweeping down and
            // back, longer and denser toward the back of the neck.
            var rng = SplitMix64(seed: 0x4AC)
            for k in 0..<46 {
                let t = CGFloat(rng.nextDouble(0, 1))
                let x = -0.44 + t * 0.66
                let y = CGFloat(rng.nextDouble(-0.35, 0.22))
                let len = CGFloat(rng.nextDouble(0.07, 0.15)) * (1.2 - t * 0.5)
                let sweep = CGFloat(rng.nextDouble(0.01, 0.04))
                c.brush([P(x, y), P(x - sweep * 0.4, y - len * 0.55), P(x - sweep, y - len)],
                        width: pen * (k % 3 == 0 ? 0.8 : 0.55), start: 0.7, end: 0.05)
            }
        }
        // A fringe of feathers where the head meets the neck.
        for k in 0..<7 {
            let x = -0.22 + CGFloat(k) * 0.055
            let y = 0.24 - abs(CGFloat(k) - 3) * 0.008
            c.brush([P(x - 0.025, y + 0.01), P(x, y - 0.05), P(x + 0.02, y + 0.005)], width: pen * 0.7, start: 0.3, end: 0.1)
        }
        c.brush([P(-0.3, 0.3), P(-0.37, 0.0), P(-0.44, -0.35)], width: 0.024, start: 0.5, end: 0.8)
        c.brush([P(0.13, 0.24), P(0.19, -0.05), P(0.25, -0.35)], width: 0.022, start: 0.5, end: 0.8)

        // Comb: a single serrated blade, textured.
        var comb: [CGPoint] = [P(-0.2, 0.62), P(-0.33, 0.74)]
        let peaks: [(CGFloat, CGFloat)] = [(-0.24, 0.9), (-0.13, 0.99), (-0.01, 1.03), (0.1, 0.99), (0.19, 0.88)]
        var x0: CGFloat = -0.27
        for (px, py) in peaks {
            comb.append(P(px, py))
            x0 = px + 0.055
            comb.append(P(x0, py - 0.12))
        }
        comb += [P(0.24, 0.72), P(0.16, 0.64), P(0.0, 0.66)]
        _ = c.mass(comb, paint: .dense)
        c.brushLoop(comb, width: pen * 1.2)

        // Head.
        let head = [P(-0.31, 0.42), P(-0.24, 0.6), P(-0.08, 0.69), P(0.12, 0.67), P(0.23, 0.58), P(0.27, 0.5),
                    P(0.25, 0.37), P(0.14, 0.25), P(-0.04, 0.21), P(-0.22, 0.26)]
        let headPath = c.mass(head, paint: .paper)
        c.clipped(to: headPath) { c in
            // Bare skin round the eye and down to the beak.
            _ = c.mass([P(0.0, 0.58), P(0.18, 0.61), P(0.3, 0.52), P(0.28, 0.33), P(0.14, 0.3), P(0.0, 0.4)], paint: .light)
            // Feather texture on the crown and back of the head.
            var rng = SplitMix64(seed: 0x4ED)
            for _ in 0..<22 {
                let x = CGFloat(rng.nextDouble(-0.3, 0.02)), y = CGFloat(rng.nextDouble(0.28, 0.66))
                c.brush([P(x + 0.03, y + 0.02), P(x, y), P(x - 0.02, y - 0.04)], width: pen * 0.5, start: 0.6, end: 0.05)
            }
        }
        c.brushLoop(head, width: 0.026)

        // Earlobe.
        let lobe = InkCanvas.ellipsePoints(center: P(0.02, 0.31), rx: 0.028, ry: 0.036, count: 9)
        _ = c.mass(lobe, paint: .light)
        c.brush(Array(lobe.prefix(6)), width: pen * 0.6, start: 0.3, end: 0.3)

        // Beak: a hooked upper mandible over a shorter lower one.
        let upper = [P(0.24, 0.525), P(0.34, 0.52), P(0.45, 0.47), P(0.5, 0.405), P(0.47, 0.41), P(0.38, 0.43), P(0.25, 0.44)]
        _ = c.mass(upper, paint: .paper)
        c.clipped(to: c.path(upper, closed: true)) { c in
            _ = c.mass([P(0.24, 0.47), P(0.5, 0.42), P(0.5, 0.38), P(0.24, 0.43)], paint: .light)
        }
        c.brushLoop(upper, width: pen * 1.1)
        let lower = [P(0.25, 0.43), P(0.38, 0.418), P(0.45, 0.4), P(0.38, 0.385), P(0.25, 0.375)]
        _ = c.mass(lower, paint: .paper)
        c.brushLoop(lower, width: pen)
        c.brush([P(0.29, 0.49), P(0.33, 0.495)], width: pen * 0.9, start: 0.8, end: 0.3)

        // Wattle, hanging under the beak.
        let wattle = [P(0.17, 0.36), P(0.27, 0.36), P(0.28, 0.25), P(0.23, 0.13), P(0.17, 0.17), P(0.15, 0.28)]
        _ = c.mass(wattle, paint: .dense)
        c.brushLoop(wattle, width: pen)

        // The eye: a ring of bare skin, a pale iris (the pupil is live).
        let (e, r) = profileEye[0]
        let ring = InkCanvas.ellipsePoints(center: e, rx: r * 1.45, ry: r * 1.35, count: 12)
        _ = c.mass(ring, paint: .light)
        c.brushLoop(ring, width: pen * 0.7)
        let iris = InkCanvas.ellipsePoints(center: e, rx: r, ry: r, count: 12)
        _ = c.mass(iris, paint: .dots(0.08))
        c.brushLoop(iris, width: pen * 1.1)
        c.brush([P(e.x - r * 1.5, e.y + r * 1.0), P(e.x, e.y + r * 1.55), P(e.x + r * 1.45, e.y + r * 0.95)], width: pen * 0.6,
                start: 0.3, end: 0.1)
    }
}
