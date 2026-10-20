/// Match, round, turn and damage rules (spec A6.4, A6.5).
///
/// Pure value type: the same engine runs vs-AI matches on the device and will be
/// mirrored by the server for online play.
public struct MatchSetup: Codable, Equatable, Sendable {
    public var seed: UInt64
    public var arena: ArenaProfile.ID
    public var roundsToWin: Int
    /// Decided by the toss (index 0 or 1).
    public var firstShooter: Int
    /// How hard each hit is (wind, knockback).
    public var challenge: HitChallenge

    public init(seed: UInt64, arena: ArenaProfile.ID, roundsToWin: Int, firstShooter: Int,
                challenge: HitChallenge = .medium) {
        self.seed = seed
        self.arena = arena
        self.roundsToWin = roundsToWin
        self.firstShooter = firstShooter
        self.challenge = challenge
    }

    /// The toss result for a seed (A6.9): shared by client and server.
    public static func tossWinner(seed: UInt64) -> Int {
        Int(SplitMix64.hash(seed, 0x7055) & 1)
    }
}

public enum MatchPhase: Codable, Equatable, Sendable {
    case awaitingShot
    case roundOver(winner: Int)
    case matchOver(winner: Int)
}

public enum RoundEndReason: String, Codable, Sendable {
    case knockout, turnLimit, suddenDeath
}

public struct MatchState: Codable, Equatable, Sendable {
    public var setup: MatchSetup
    public var phase: MatchPhase = .awaitingShot
    public var round = 1
    public var roundsWon = [0, 0]
    public var roundFirstShooter: Int
    public var health: [Int]
    public var shotsThisRound = [0, 0]
    public var currentShooter: Int
    /// Global, strictly increasing turn number (A8.2).
    public var turn = 1
    /// True when the current shooter is replying at 0 health (equal-shots rule).
    public var lastBreath = false
    /// Pairs of shots completed this round (drives the wind shifts).
    public var pair = 0
    /// 0 = normal play; n = the n-th sudden-death pair of this round.
    public var suddenDeath = 0
    /// Sudden-death results of the current pair: miss distance (0 = hit) and damage.
    public var suddenDeathShots: [SuddenDeathShot?] = [nil, nil]
    public var conditions: RoundConditions
    /// The wind in world terms (positive blows toward archer 1). Its direction
    /// is fixed for the whole match; its strength changes only after an arrow
    /// strikes an archer. Both players shoot in exactly this wind.
    public var windWorld: Double = 0
    /// Per-player stats for the result screen.
    public var hitsLanded = [0, 0]
    public var headshots = [0, 0]

    public var isOver: Bool {
        if case .matchOver = phase { return true }
        return false
    }

    public var winner: Int? {
        if case let .matchOver(w) = phase { return w }
        return nil
    }
}

public struct SuddenDeathShot: Codable, Equatable, Sendable {
    public var missDistance: Double
    public var damage: Int
}

public struct TurnReport: Codable, Equatable, Sendable {
    public enum Event: Codable, Equatable, Sendable {
        /// Play continues; `lastBreath` = the next shooter replies at 0 health.
        case nextTurn(shooter: Int, lastBreath: Bool)
        /// The wind's strength changed after a strike (world terms, same direction).
        case windChanged(Double)
        /// A hit knocked an archer back; `offset` is their new distance from
        /// their starting spot.
        case knockedBack(archer: Int, offset: Double)
        case suddenDeath(pair: Int)
        case roundOver(winner: Int, reason: RoundEndReason)
        case matchOver(winner: Int)
    }

    public var turn: Int
    public var round: Int
    public var shooter: Int
    public var input: ShotInput
    public var outcome: ShotOutcome
    /// Archer that took damage, if any.
    public var damagedArcher: Int?
    public var damage: Int
    public var health: [Int]
    /// Distance from the impact to the target's nearest hitbox, when it missed.
    public var missDistance: Double?
    /// Set when the miss landed within the near-miss distance (A6.9).
    public var nearMiss: Double?
    public var events: [Event]
}

public struct MatchEngine: Sendable {
    public private(set) var state: MatchState
    public let config: GameConfig

    public init(setup: MatchSetup, config: GameConfig = .default) {
        self.config = config
        let arena = ArenaProfile.profile(for: setup.arena)
        let seed = RoundConditions.roundSeed(matchSeed: setup.seed, round: 1)
        state = MatchState(
            setup: setup,
            roundFirstShooter: setup.firstShooter,
            health: [config.damage.startHealth, config.damage.startHealth],
            currentShooter: setup.firstShooter,
            conditions: .generatePlayable(seed: seed, arena: arena, config: config)
        )
        // One direction for the whole match, picked by the seed.
        let sign: Double = SplitMix64.hash(setup.seed, 0x5141D) & 1 == 0 ? 1 : -1
        state.windWorld = fittedWind(scaledWind(sign * abs(state.conditions.windRelative)))
        syncWind()
    }

    // MARK: Wind

    /// Points the shared world wind at the current shooter (the simulator
    /// takes wind relative to whoever is shooting).
    private mutating func syncWind() {
        state.conditions.windRelative = state.windWorld * RoundConditions.facing(state.currentShooter)
    }

    /// True when both archers can still hit each other in this world wind.
    private func windAllowsHits(_ world: Double) -> Bool {
        var c = state.conditions
        for shooter in [0, 1] {
            c.windRelative = world * RoundConditions.facing(shooter)
            if !ShotSearch.isHittable(c, shooter: shooter, config: config) { return false }
        }
        return true
    }

    /// The strongest wind up to `world` (same direction) that keeps the round fair.
    private func fittedWind(_ world: Double) -> Double {
        var w = world
        while w != 0 && !windAllowsHits(w) { w = w > 0 ? max(0, w - 0.5) : min(0, w + 0.5) }
        return w
    }

    /// The arena's wind, scaled by the challenge, on the 0.5 m/s² grid.
    private func scaledWind(_ w: Double) -> Double {
        (w * state.setup.challenge.windScale * 2).rounded() / 2
    }

    /// After a hit: the target is shoved back from where they stood. Eased if
    /// it would leave either archer without a possible hit.
    private mutating func knockBack(_ victim: Int) -> Double? {
        let ch = state.setup.challenge
        var rng = SplitMix64(seed: SplitMix64.hash(state.setup.seed, 0xB0B0, UInt64(state.turn)))
        let old = state.conditions.archerOffsets[victim]
        var push = Double(rng.nextInt(in: ch.knockbackTenths)) / 10
        push = min(push, ch.maxKnockback - old)
        while push >= 0.5 {
            state.conditions.archerOffsets[victim] = old + push
            if windAllowsHits(state.windWorld) || windAllowsHits(0) { break }
            push -= 0.5
        }
        if push < 0.5 { state.conditions.archerOffsets[victim] = old; return nil }
        state.windWorld = fittedWind(state.windWorld)
        return old + push
    }

    /// After a strike: a new strength, same direction.
    private mutating func shiftWindAfterStrike() -> Double? {
        let arena = ArenaProfile.profile(for: state.setup.arena)
        var rng = SplitMix64(seed: SplitMix64.hash(state.setup.seed, 0x5711CE, UInt64(state.turn)))
        let sign: Double = state.windWorld < 0 ? -1 : (state.windWorld > 0 ? 1 :
            (SplitMix64.hash(state.setup.seed, 0x5141D) & 1 == 0 ? 1 : -1))
        let current = abs(state.windWorld)
        let lo = Int((arena.minWind * state.setup.challenge.windScale * 2).rounded())
        let hi = Int((arena.maxWind * state.setup.challenge.windScale * 2).rounded())
        let steps = Array(lo...max(lo, hi)).map { Double($0) * 0.5 }.filter { $0 != current }
        guard !steps.isEmpty else { return nil }
        let next = fittedWind(sign * steps[rng.nextInt(in: 0...(steps.count - 1))])
        guard next != state.windWorld else { return nil }
        state.windWorld = next
        return next
    }

    public static func baseDamage(_ part: BodyPart, _ cfg: DamageConfig) -> Int {
        switch part {
        case .head: return cfg.head
        case .body: return cfg.body
        case .legs: return cfg.legs
        }
    }

    /// Simulates the current shooter's shot without changing state.
    public func preview(_ input: ShotInput, recordPath: Bool = true) -> ShotOutcome {
        ShotSimulator.simulate(input, shooter: state.currentShooter, conditions: state.conditions,
                               config: config, recordPath: recordPath)
    }

    /// Plays the current shooter's shot. `braceMultiplier` is the defender's brace
    /// result (1, 0.75 or 0.5; A6.10).
    @discardableResult
    public mutating func submit(_ rawInput: ShotInput, braceMultiplier: Double = 1) -> TurnReport {
        precondition(state.phase == .awaitingShot, "submit called while \(state.phase)")
        let input = rawInput.clamped(config.aim)
        let shooter = state.currentShooter
        let target = 1 - shooter
        let outcome = preview(input)

        var damage = 0
        var damaged: Int?
        if let hitIndex = outcome.hitArcher, let part = outcome.hitPart {
            let base = MatchEngine.baseDamage(part, config.damage)
            let mult = hitIndex == target ? braceMultiplier : 1
            damage = Int((Double(base) * mult).rounded(.down))
            damaged = hitIndex
            if state.suddenDeath == 0 {
                state.health[hitIndex] = max(0, state.health[hitIndex] - damage)
            }
            if hitIndex == target {
                state.hitsLanded[shooter] += 1
                if part == .head { state.headshots[shooter] += 1 }
            }
        }

        let targetFeet = state.conditions.archerPosition(target)
        let missDistance: Double? = outcome.hitArcher == target
            ? nil : Hitbox.distance(from: outcome.point, feet: targetFeet, scale: config.physics.archerScale)
        let nearMiss = missDistance.flatMap { $0 <= config.physics.nearMissDistance ? $0 : nil }

        let turn = state.turn
        state.turn += 1
        state.shotsThisRound[shooter] += 1

        var events: [TurnReport.Event]
        if state.suddenDeath > 0 {
            events = resolveSuddenDeath(shooter: shooter, missDistance: missDistance ?? 0,
                                        damage: outcome.hitArcher == target ? damage : 0)
        } else {
            events = resolveNormal(shooter: shooter)
        }
        // A strike knocks the target back and changes the wind's strength.
        if let victim = outcome.hitArcher, state.suddenDeath == 0, case .awaitingShot = state.phase, events.contains(where: {
            if case .nextTurn = $0 { return true }; return false
        }) {
            if let w = shiftWindAfterStrike() { events.insert(.windChanged(w), at: 0) }
            if let off = knockBack(victim) { events.insert(.knockedBack(archer: victim, offset: off), at: 0) }
        }
        syncWind()
        if case let .roundOver(winner, _)? = events.last {
            state.roundsWon[winner] += 1
            if state.roundsWon[winner] >= state.setup.roundsToWin {
                state.phase = .matchOver(winner: winner)
                events.append(.matchOver(winner: winner))
            } else {
                state.phase = .roundOver(winner: winner)
            }
        }

        return TurnReport(
            turn: turn, round: state.round, shooter: shooter, input: input, outcome: outcome,
            damagedArcher: damaged, damage: damage, health: state.health,
            missDistance: missDistance, nearMiss: nearMiss, events: events
        )
    }

    private mutating func resolveNormal(shooter: Int) -> [TurnReport.Event] {
        let first = state.roundFirstShooter
        let second = 1 - first
        if shooter == first {
            // Equal-shots rule: the second shooter always gets the reply shot.
            state.currentShooter = second
            state.lastBreath = state.health[second] == 0
            return [.nextTurn(shooter: second, lastBreath: state.lastBreath)]
        }
        state.lastBreath = false
        let firstDown = state.health[first] == 0
        let secondDown = state.health[second] == 0
        if firstDown && secondDown {
            return startSuddenDeath()
        }
        if firstDown { return [.roundOver(winner: second, reason: .knockout)] }
        if secondDown { return [.roundOver(winner: first, reason: .knockout)] }
        let limit = config.rules.maxShotsPerPlayerPerRound
        if state.shotsThisRound[first] >= limit && state.shotsThisRound[second] >= limit {
            if state.health[first] == state.health[second] { return startSuddenDeath() }
            let winner = state.health[first] > state.health[second] ? first : second
            return [.roundOver(winner: winner, reason: .turnLimit)]
        }
        state.currentShooter = first
        state.pair += 1
        return [.nextTurn(shooter: first, lastBreath: false)]
    }

    private mutating func startSuddenDeath() -> [TurnReport.Event] {
        state.suddenDeath += 1
        state.suddenDeathShots = [nil, nil]
        state.lastBreath = false
        let seed = RoundConditions.roundSeed(matchSeed: state.setup.seed, round: state.round,
                                             suddenDeath: state.suddenDeath)
        state.conditions = .generatePlayable(seed: seed, arena: ArenaProfile.profile(for: state.setup.arena),
                                             config: config)
        state.currentShooter = state.roundFirstShooter
        state.windWorld = fittedWind(state.windWorld)
        syncWind()
        return [.suddenDeath(pair: state.suddenDeath)]
    }

    private mutating func resolveSuddenDeath(shooter: Int, missDistance: Double, damage: Int) -> [TurnReport.Event] {
        state.suddenDeathShots[shooter] = SuddenDeathShot(missDistance: damage > 0 ? 0 : missDistance, damage: damage)
        guard let a = state.suddenDeathShots[0], let b = state.suddenDeathShots[1] else {
            state.currentShooter = 1 - shooter
            return [.nextTurn(shooter: 1 - shooter, lastBreath: false)]
        }
        var winner: Int?
        if a.damage > 0 || b.damage > 0 {
            if a.damage != b.damage { winner = a.damage > b.damage ? 0 : 1 }
        } else if a.missDistance != b.missDistance {
            winner = a.missDistance < b.missDistance ? 0 : 1
        }
        if let winner {
            return [.roundOver(winner: winner, reason: .suddenDeath)]
        }
        return startSuddenDeath()
    }

    /// Starts the next round after `.roundOver`. The first shooter alternates.
    public mutating func startNextRound() {
        guard case .roundOver = state.phase else { return }
        state.round += 1
        state.roundFirstShooter = 1 - state.roundFirstShooter
        state.currentShooter = state.roundFirstShooter
        state.health = [config.damage.startHealth, config.damage.startHealth]
        state.shotsThisRound = [0, 0]
        state.lastBreath = false
        state.suddenDeath = 0
        state.suddenDeathShots = [nil, nil]
        state.pair = 0
        let seed = RoundConditions.roundSeed(matchSeed: state.setup.seed, round: state.round)
        state.conditions = .generatePlayable(seed: seed, arena: ArenaProfile.profile(for: state.setup.arena),
                                             config: config)
        // Same wind carries over; eased only if the new ground makes it unfair.
        state.windWorld = fittedWind(state.windWorld)
        syncWind()
        state.phase = .awaitingShot
    }

    /// Ends the match with the other player as winner (pause → Forfeit).
    public mutating func forfeit(by player: Int) {
        state.phase = .matchOver(winner: 1 - player)
    }
}
