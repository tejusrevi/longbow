/// How hard each individual hit is (the three difficulties). Both archers play
/// by the same numbers; the AI's own accuracy is set separately.
public enum HitChallenge: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard

    /// Multiplier on the arena's wind range.
    public var windScale: Double {
        switch self {
        case .easy: return 0.5
        case .medium: return 1
        case .hard: return 1.5
        }
    }

    /// How far a hit knocks the target back, in metres (tenths, for the seeded pick).
    public var knockbackTenths: ClosedRange<Int> {
        switch self {
        case .easy: return 15...25
        case .medium: return 30...45
        case .hard: return 50...70
        }
    }

    /// Furthest an archer can be pushed from their starting spot in a round.
    public var maxKnockback: Double {
        switch self {
        case .easy: return 6
        case .medium: return 10
        case .hard: return 14
        }
    }

    /// Share of the trajectory the aim guide shows, 0...100.
    public var aimGuidePercent: Double {
        switch self {
        case .easy: return 35
        case .medium: return 15
        case .hard: return 0
        }
    }
}
