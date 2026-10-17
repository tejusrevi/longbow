import Foundation

/// Computer opponent (spec A7.1). Runs on the device only; it does not need to be
/// deterministic across platforms, but it is seeded so tests are repeatable.
public enum AIDifficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard

    /// Aiming error σ: angle in degrees, power as a fraction (A7.1 step 3).
    public var sigma: (angle: Double, power: Double) {
        switch self {
        case .easy: return (6, 0.08)
        case .medium: return (3, 0.04)
        case .hard: return (1.2, 0.015)
        }
    }

    public var aimPart: BodyPart { self == .hard ? .head : .body }

    /// Brace odds (A6.10/A7.1 step 6): perfect, good.
    public var braceOdds: (perfect: Double, good: Double) {
        switch self {
        case .easy: return (0, 0)
        case .medium: return (0, 0.4)
        case .hard: return (0.2, 0.7)
        }
    }
}

public struct AISearch: Sendable {
    /// Angle step for the power binary search (A7.1: 2°).
    public var angleStepTenths = 20
    /// Fine search around the best coarse candidate.
    public var refineRadiusTenths = 20
    public var refineStepTenths = 2
    public var refineRadiusPermille = 20
    public var refineStepPermille = 2

    public init() {}

    /// Cheaper search for automated soak tests.
    public static let fast: AISearch = {
        var s = AISearch()
        s.angleStepTenths = 40
        s.refineStepTenths = 5
        s.refineStepPermille = 5
        return s
    }()
}

public struct AIPlayer: Sendable {
    public let difficulty: AIDifficulty
    public var search: AISearch
    private var rng: SplitMix64
    /// Misses in the current round; each reduces the error by 30 % (A7.1 step 4).
    public private(set) var missesThisRound = 0
    private var round = 0

    public init(difficulty: AIDifficulty, seed: UInt64, search: AISearch = .init()) {
        self.difficulty = difficulty
        self.search = search
        rng = SplitMix64(seed: seed)
    }

    /// Picks the shot for the current shooter of `engine`.
    public mutating func chooseShot(engine: MatchEngine) -> ShotInput {
        let state = engine.state
        if state.round != round {
            round = state.round
            missesThisRound = 0
        }
        let best = bestShot(engine: engine)
        let scale = pow(0.7, Double(missesThisRound))
        let sigma = difficulty.sigma
        let angle = best.angleDegrees + gaussian() * sigma.angle * scale
        let power = best.power + gaussian() * sigma.power * scale
        return ShotInput.quantise(angleDegrees: angle, power: power, aim: engine.config.aim)
    }

    /// Call after each of the AI's own shots so it can "correct" like a human.
    public mutating func observe(_ report: TurnReport) {
        if report.outcome.hitArcher != 1 - report.shooter {
            missesThisRound += 1
        }
    }

    /// Brace multiplier the AI achieves when defending.
    public mutating func braceMultiplier() -> Double {
        let odds = difficulty.braceOdds
        let r = rng.nextUnit()
        if r < odds.perfect { return 0.5 }
        if r < odds.perfect + odds.good { return 0.75 }
        return 1
    }

    /// Think time in seconds (A7.1 step 5, shortened: the bow pick-up and draw
    /// animation already reads as thinking).
    public mutating func thinkTime() -> Double {
        rng.nextDouble(0.5, 1.0)
    }

    // MARK: - Search

    public func bestShot(engine: MatchEngine) -> ShotInput {
        let state = engine.state
        let shooter = state.currentShooter
        let found = ShotSearch.search(conditions: state.conditions, shooter: shooter, config: engine.config,
                                      aimPart: difficulty.aimPart, angleStepTenths: search.angleStepTenths)
        if found.hitsAimedPart { return found.input }
        // Polish around the best candidate.
        let aim = engine.config.aim
        let target = 1 - shooter
        let aimPoint = Hitbox.center(of: difficulty.aimPart, feet: state.conditions.archerPosition(target),
                                     scale: engine.config.physics.archerScale)
        var best = found.input
        var bestScore = found.hits ? -1 : found.miss
        var da = -search.refineRadiusTenths
        while da <= search.refineRadiusTenths {
            var dp = -search.refineRadiusPermille
            while dp <= search.refineRadiusPermille {
                let input = ShotInput(angleTenths: found.input.angleTenths + da,
                                      powerPermille: found.input.powerPermille + dp).clamped(aim)
                let o = engine.preview(input, recordPath: false)
                let s: Double = o.hitArcher == target ? (o.hitPart == difficulty.aimPart ? -2 : -1)
                    : (o.hitArcher == shooter ? 1e9 : o.point.distance(to: aimPoint))
                if s < bestScore { bestScore = s; best = input }
                if s == -2 { return best }
                dp += search.refineStepPermille
            }
            da += search.refineStepTenths
        }
        return best
    }

    private mutating func gaussian() -> Double {
        // Box–Muller. AI only — never part of the shared simulation.
        let u1 = max(rng.nextUnit(), 1e-12)
        let u2 = rng.nextUnit()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
