/// Golden test vector format shared by client and server tests (spec A6.3).
/// Doubles are stored as IEEE-754 bit patterns (hex) so comparisons are exact.
public struct GoldenFile: Codable, Sendable {
    public var version: Int
    public var note: String
    public var shots: [GoldenShot]

    public init(version: Int, note: String, shots: [GoldenShot]) {
        self.version = version
        self.note = note
        self.shots = shots
    }
}

public struct GoldenShot: Codable, Sendable {
    public var id: Int
    /// Round seed as a hex string (UInt64 does not fit a JSON number).
    public var seed: String
    public var arena: ArenaProfile.ID
    public var shooter: Int
    public var angleTenths: Int
    public var powerPermille: Int
    public var expected: Expected

    public struct Expected: Codable, Equatable, Sendable {
        /// archer | terrain | obstacle | outOfBounds | timeout
        public var impact: String
        public var index: Int?
        public var part: BodyPart?
        public var xBits: String
        public var yBits: String
        /// Human-readable copies of x and y; not used for comparison.
        public var x: Double
        public var y: Double
        public var steps: Int
    }

    public init(id: Int, seed: UInt64, arena: ArenaProfile.ID, shooter: Int, input: ShotInput, outcome: ShotOutcome) {
        self.id = id
        self.seed = GoldenShot.hex(seed)
        self.arena = arena
        self.shooter = shooter
        angleTenths = input.angleTenths
        powerPermille = input.powerPermille
        expected = GoldenShot.expected(for: outcome)
    }

    public var seedValue: UInt64 { UInt64(seed.dropFirst(2), radix: 16) ?? 0 }
    public var input: ShotInput { ShotInput(angleTenths: angleTenths, powerPermille: powerPermille) }

    public static func hex(_ v: UInt64) -> String {
        let s = String(v, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: 16 - s.count) + s
    }

    public static func expected(for o: ShotOutcome) -> Expected {
        var kind = ""
        var index: Int?
        var part: BodyPart?
        switch o.impact {
        case let .archer(i, p): kind = "archer"; index = i; part = p
        case .terrain: kind = "terrain"
        case let .obstacle(i): kind = "obstacle"; index = i
        case .outOfBounds: kind = "outOfBounds"
        case .timeout: kind = "timeout"
        }
        return Expected(impact: kind, index: index, part: part,
                        xBits: hex(o.point.x.bitPattern), yBits: hex(o.point.y.bitPattern),
                        x: o.point.x, y: o.point.y, steps: o.steps)
    }
}
