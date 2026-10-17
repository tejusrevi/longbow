/// Minimal 2D geometry for the simulation. Only basic arithmetic and `sqrt`
/// (correctly rounded in IEEE-754, so identical in Swift and JavaScript).
public struct Vec2: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }

    public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    public var lengthSquared: Double { x * x + y * y }
    public var length: Double { lengthSquared.squareRoot() }

    public func distance(to o: Vec2) -> Double { (self - o).length }
}

public enum HitShape: Codable, Equatable, Sendable {
    case circle(center: Vec2, radius: Double)
    /// Axis-aligned rectangle.
    case rect(min: Vec2, max: Vec2)

    /// Parameter t in [0, 1] where the segment p0→p1 first touches the shape,
    /// or nil if it does not. A segment starting inside returns 0.
    public func entry(from p0: Vec2, to p1: Vec2) -> Double? {
        switch self {
        case let .circle(c, r):
            let d = p1 - p0
            let f = p0 - c
            let cc = f.dot(f) - r * r
            if cc <= 0 { return 0 }
            let a = d.dot(d)
            if a == 0 { return nil }
            let b = 2 * f.dot(d)
            let disc = b * b - 4 * a * cc
            if disc < 0 { return nil }
            let t = (-b - disc.squareRoot()) / (2 * a)
            return (t >= 0 && t <= 1) ? t : nil
        case let .rect(mn, mx):
            // Liang–Barsky slab clipping.
            var t0 = 0.0
            var t1 = 1.0
            let d = p1 - p0
            func clip(_ p: Double, _ q: Double) -> Bool {
                if p == 0 { return q >= 0 }
                let r = q / p
                if p < 0 {
                    if r > t1 { return false }
                    if r > t0 { t0 = r }
                } else {
                    if r < t0 { return false }
                    if r < t1 { t1 = r }
                }
                return true
            }
            guard clip(-d.x, p0.x - mn.x), clip(d.x, mx.x - p0.x),
                  clip(-d.y, p0.y - mn.y), clip(d.y, mx.y - p0.y) else { return nil }
            return t0
        }
    }

    /// Distance from a point to the shape (0 inside).
    public func distance(to p: Vec2) -> Double {
        switch self {
        case let .circle(c, r):
            return max(0, p.distance(to: c) - r)
        case let .rect(mn, mx):
            let dx = max(mn.x - p.x, 0, p.x - mx.x)
            let dy = max(mn.y - p.y, 0, p.y - mx.y)
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    public func offset(by v: Vec2) -> HitShape {
        switch self {
        case let .circle(c, r): return .circle(center: c + v, radius: r)
        case let .rect(mn, mx): return .rect(min: mn + v, max: mx + v)
        }
    }
}
