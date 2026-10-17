import CoreGraphics
import LongbowCore

/// Hand-inked strokes. A pen line is never one width: it swells where the
/// nib presses, thins and flicks off at the ends, and wavers a little. These
/// helpers draw strokes as filled shapes with that varying width, which is
/// what makes the artwork read as drawn rather than generated.
extension InkCanvas {
    mutating func rand(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat(rng.nextDouble(Double(a), Double(b))) }

    /// Catmull-Rom centreline through `pts`, sampled densely.
    static func smoothed(_ pts: [CGPoint], closed: Bool, perSegment: Int = 10) -> [CGPoint] {
        guard pts.count > 2 else {
            guard pts.count == 2 else { return pts }
            return (0...perSegment).map { i in
                let t = CGFloat(i) / CGFloat(perSegment)
                return CGPoint(x: pts[0].x + (pts[1].x - pts[0].x) * t, y: pts[0].y + (pts[1].y - pts[0].y) * t)
            }
        }
        var p = pts
        if closed { p.append(pts[0]) }
        let n = p.count
        var out: [CGPoint] = []
        for i in 0..<(n - 1) {
            let p0 = i > 0 ? p[i - 1] : (closed ? p[n - 2] : p[i])
            let p1 = p[i], p2 = p[i + 1]
            let p3 = i + 2 < n ? p[i + 2] : (closed ? p[1] : p2)
            for k in 0..<perSegment {
                let t = CGFloat(k) / CGFloat(perSegment)
                let t2 = t * t, t3 = t2 * t
                func c(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (-a + 3 * b - 3 * cc + d) * t3)
                }
                out.append(CGPoint(x: c(p0.x, p1.x, p2.x, p3.x), y: c(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        if !closed { out.append(p[n - 1]) }
        return out
    }

    /// Straight segments between corners, sampled densely (for angular shapes).
    static func polyline(_ pts: [CGPoint], closed: Bool, perSegment: Int = 8) -> [CGPoint] {
        var p = pts
        if closed { p.append(pts[0]) }
        var out: [CGPoint] = []
        for i in 0..<(p.count - 1) {
            for k in 0..<perSegment {
                let t = CGFloat(k) / CGFloat(perSegment)
                out.append(CGPoint(x: p[i].x + (p[i + 1].x - p[i].x) * t, y: p[i].y + (p[i + 1].y - p[i].y) * t))
            }
        }
        if !closed, let last = p.last { out.append(last) }
        return out
    }

    /// A tapered stroke through `points` (smoothed). `start`/`end` are the
    /// width fractions at the tips; `swell` is how much of the length the
    /// stroke takes to reach full width.
    mutating func brush(_ points: [CGPoint], width: CGFloat, start: CGFloat = 0.25, end: CGFloat = 0.12,
                        swell: CGFloat = 0.3, paint: InkPaint = .ink, wobble: CGFloat? = nil) {
        let w = wobble ?? self.wobble
        let jittered = points.map { CGPoint(x: $0.x + rand(-w, w), y: $0.y + rand(-w, w)) }
        let dense = Self.smoothed(jittered, closed: false)
        let phase = rand(0, 6.28), freq = rand(5, 9)
        brushDense(dense, paint: paint) { t, _ in
            let a = min(1, t / max(swell, 0.01)), b = min(1, (1 - t) / max(swell, 0.01))
            let ease = { (x: CGFloat) in x * x * (3 - 2 * x) }
            let prof = min(start + (1 - start) * ease(a), end + (1 - end) * ease(b))
            return width * prof * (1 + 0.1 * sin(t * freq + phase))
        }
    }

    /// An inked outline around a closed shape: thicker on the shadow side
    /// (lower right), thin on the lit side, and the pen overlaps a little
    /// where it started, tapering off.
    mutating func brushLoop(_ points: [CGPoint], width: CGFloat, angular: Bool = false, paint: InkPaint = .ink) {
        let w = self.wobble
        let jittered = points.map { CGPoint(x: $0.x + rand(-w, w), y: $0.y + rand(-w, w)) }
        var dense = angular ? Self.polyline(jittered, closed: true) : Self.smoothed(jittered, closed: true)
        guard dense.count > 4 else { return }
        // Start somewhere on the upper left, and overlap past the start.
        let startIndex = Int(rand(0, 0.25) * CGFloat(dense.count))
        dense = Array(dense[startIndex...] + dense[..<startIndex])
        let overlap = max(2, dense.count / 14)
        dense += dense.prefix(overlap)
        let c = CGPoint(x: dense.map(\.x).reduce(0, +) / CGFloat(dense.count),
                        y: dense.map(\.y).reduce(0, +) / CGFloat(dense.count))
        let light = CGPoint(x: -0.6, y: 0.8)
        let phase = rand(0, 6.28)
        brushDense(dense, paint: paint) { t, p in
            let o = CGPoint(x: p.x - c.x, y: p.y - c.y)
            let len = max(0.0001, hypot(o.x, o.y))
            let lit = (o.x * light.x + o.y * light.y) / len // 1 = facing the light
            let shade = 0.45 + 0.55 * (1 - lit) / 2
            let tipIn = min(1, t / 0.05), tipOut = min(1, (1 - t) / 0.06)
            let tips = 0.2 + 0.8 * min(tipIn, tipOut)
            return width * shade * tips * (1 + 0.08 * sin(t * 13 + phase))
        }
    }

    /// Fills the ribbon around a dense centreline with width `widthAt(t, p)`.
    mutating func brushDense(_ dense: [CGPoint], paint: InkPaint, widthAt: (CGFloat, CGPoint) -> CGFloat) {
        guard dense.count > 1 else { return }
        var lengths: [CGFloat] = [0]
        for i in 1..<dense.count {
            lengths.append(lengths[i - 1] + hypot(dense[i].x - dense[i - 1].x, dense[i].y - dense[i - 1].y))
        }
        let total = max(lengths.last ?? 1, 0.0001)
        var left: [CGPoint] = [], right: [CGPoint] = []
        var firstR: CGFloat = 0, lastR: CGFloat = 0
        for i in 0..<dense.count {
            let a = dense[max(0, i - 1)], b = dense[min(dense.count - 1, i + 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let l = max(0.000001, hypot(dx, dy))
            let n = CGPoint(x: -dy / l, y: dx / l)
            let r = widthAt(lengths[i] / total, dense[i]) / 2
            if i == 0 { firstR = r }
            lastR = r
            left.append(CGPoint(x: dense[i].x + n.x * r, y: dense[i].y + n.y * r))
            right.append(CGPoint(x: dense[i].x - n.x * r, y: dense[i].y - n.y * r))
        }
        let path = CGMutablePath()
        path.addLines(between: left + right.reversed())
        path.closeSubpath()
        ctx.setFillColor(paint.cgColor)
        ctx.addPath(path)
        ctx.fillPath(using: .winding)
        // Round nib at both ends (filled separately so overlaps never cancel).
        for (p, r) in [(dense[0], firstR), (dense[dense.count - 1], lastR)] where r > 0 {
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
    }

    /// An organic filled shape (hair, beards): smoothed, no outline.
    mutating func mass(_ points: [CGPoint], paint: InkPaint = .ink, angular: Bool = false) -> CGPath {
        let w = self.wobble
        let jittered = points.map { CGPoint(x: $0.x + rand(-w, w), y: $0.y + rand(-w, w)) }
        let dense = angular ? Self.polyline(jittered, closed: true) : Self.smoothed(jittered, closed: true)
        let p = CGMutablePath()
        p.addLines(between: dense)
        p.closeSubpath()
        fill(p, paint)
        return p
    }

    /// A few loose dots, like a pen tapped on paper (stubble, freckles).
    mutating func stipple(in rect: CGRect, count: Int, radius: CGFloat, inside: ((CGPoint) -> Bool)? = nil) {
        var placed = 0, tries = 0
        while placed < count && tries < count * 8 {
            tries += 1
            let p = CGPoint(x: rand(rect.minX, rect.maxX), y: rand(rect.minY, rect.maxY))
            if let inside, !inside(p) { continue }
            dot(p, radius * rand(0.7, 1.2))
            placed += 1
        }
    }
}
