/// Mirror-symmetric terrain height function (spec A6.6, A6.7).
///
/// h(x) is built from three lookup-table sine waves, averaged with their mirror
/// image so h(x) == h(distance − x). Both archers stand on a flat 4 m pad at
/// height 0. Only table lookups and basic arithmetic — portable bit for bit.
public struct Terrain: Codable, Equatable, Sendable {
    public struct Wave: Codable, Equatable, Sendable {
        public var amplitude: Double
        public var wavelength: Double
        public var phaseDegrees: Double
    }

    public var distance: Double
    public var waves: [Wave]
    public var valleyDepth: Double
    public static let padHalfWidth = 2.0
    public static let blendWidth = 8.0
    public static let minHeight = -15.0

    public init(distance: Double, waves: [Wave], valleyDepth: Double) {
        self.distance = distance
        self.waves = waves
        self.valleyDepth = valleyDepth
    }

    private func raw(_ x: Double) -> Double {
        var sum = 0.0
        for w in waves {
            sum = sum + w.amplitude * Trig.sinLerp(degrees: w.phaseDegrees + 360.0 * x / w.wavelength)
        }
        return sum
    }

    public func height(at x: Double) -> Double {
        let d = distance
        let base = 0.5 * (raw(x) + raw(d - x)) - 0.5 * (raw(0) + raw(d))
        // Valley only between the archers; beyond them the land just rolls on.
        let u = min(max(x / d, 0), 1)
        let valley = -valleyDepth * 4.0 * u * (1.0 - u)
        let edge = min(abs(x), abs(x - d))
        var w = 0.0
        if edge > Terrain.padHalfWidth {
            let s = min(1.0, (edge - Terrain.padHalfWidth) / Terrain.blendWidth)
            w = s * s * (3.0 - 2.0 * s)
        }
        return max(Terrain.minHeight, w * (base + valley))
    }
}

public struct Obstacle: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case tree, rock, wall
    }

    public var kind: Kind
    public var x: Double
    public var baseY: Double
    /// Collision shapes in world coordinates.
    public var shapes: [HitShape]

    public static func make(_ kind: Kind, at x: Double, baseY: Double) -> Obstacle {
        let base = Vec2(x, baseY)
        let local: [HitShape]
        switch kind {
        case .tree:
            local = [
                .circle(center: Vec2(0, 5.6), radius: 2.3),
                .rect(min: Vec2(-0.25, -0.5), max: Vec2(0.25, 4.0)),
            ]
        case .rock:
            local = [.circle(center: Vec2(0, 0.3), radius: 1.1)]
        case .wall:
            local = [.rect(min: Vec2(-0.8, -0.5), max: Vec2(0.8, 6))]
        }
        return Obstacle(kind: kind, x: x, baseY: baseY, shapes: local.map { $0.offset(by: base) })
    }
}
