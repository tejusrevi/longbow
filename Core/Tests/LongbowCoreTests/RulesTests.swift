import XCTest
import LongbowCore

final class RulesTests: XCTestCase {
    /// A guaranteed hit on `part` for the current shooter, found by search.
    private func hit(_ engine: MatchEngine) -> ShotInput {
        AIPlayer(difficulty: .hard, seed: 1, search: .fast).bestShot(engine: engine)
    }

    /// A shot that drops at the shooter's own feet... well, just in front of them.
    private let dud = ShotInput(angleTenths: -100, powerPermille: 0)

    private func oneHitKills() -> GameConfig {
        var c = GameConfig()
        c.damage.head = 100; c.damage.body = 100; c.damage.legs = 100
        return c
    }

    private func engine(seed: UInt64 = 7, first: Int = 0, config: GameConfig = .init()) -> MatchEngine {
        MatchEngine(setup: MatchSetup(seed: seed, arena: .hills, roundsToWin: 3, firstShooter: first), config: config)
    }

    func testTurnsAlternateAndDudDoesNoDamage() {
        var e = engine()
        let r = e.submit(dud)
        XCTAssertEqual(r.damage, 0)
        XCTAssertEqual(r.events, [.nextTurn(shooter: 1, lastBreath: false)])
        XCTAssertEqual(e.state.currentShooter, 1)
        e.submit(dud)
        XCTAssertEqual(e.state.currentShooter, 0)
        XCTAssertEqual(e.state.turn, 3)
    }

    func testFirstShooterKnockoutGivesLastBreathReply() {
        var e = engine(config: oneHitKills())
        let r = e.submit(hit(e))
        XCTAssertNotNil(r.outcome.hitPart)
        XCTAssertEqual(e.state.health[1], 0)
        // A strike may also shift the wind's strength; the turn rule is what matters here.
        XCTAssertEqual(r.events.filter {
                           switch $0 { case .windChanged, .knockedBack: return false; default: return true }
                       },
                       [.nextTurn(shooter: 1, lastBreath: true)])
        XCTAssertTrue(e.state.lastBreath)
        let reply = e.submit(dud)
        XCTAssertEqual(reply.events, [.roundOver(winner: 0, reason: .knockout)])
        XCTAssertEqual(e.state.roundsWon, [1, 0])
    }

    func testLastBreathHitForcesSuddenDeath() {
        var e = engine(config: oneHitKills())
        e.submit(hit(e))
        let oldSeed = e.state.conditions.seed
        let reply = e.submit(hit(e))
        XCTAssertEqual(reply.events, [.suddenDeath(pair: 1)])
        XCTAssertNotEqual(e.state.conditions.seed, oldSeed, "sudden death uses fresh conditions")
        XCTAssertEqual(e.state.currentShooter, 0)
        // In sudden death the closest shot wins: a hit beats a dud.
        e.submit(hit(e))
        let end = e.submit(dud)
        XCTAssertEqual(end.events, [.roundOver(winner: 0, reason: .suddenDeath)])
    }

    func testSecondShooterKnockoutEndsRound() {
        var e = engine(config: oneHitKills())
        e.submit(dud)
        let r = e.submit(hit(e))
        XCTAssertEqual(r.events, [.roundOver(winner: 1, reason: .knockout)])
    }

    func testRoundsAlternateFirstShooterAndMatchEnds() {
        var e = engine(config: oneHitKills())
        for round in 1...3 {
            XCTAssertEqual(e.state.round, round)
            let first = e.state.currentShooter
            XCTAssertEqual(first, round % 2 == 1 ? 0 : 1)
            if first == 0 {
                e.submit(hit(e)); e.submit(dud)
            } else {
                e.submit(dud); e.submit(hit(e))
            }
            if round < 3 { e.startNextRound() }
        }
        XCTAssertEqual(e.state.phase, .matchOver(winner: 0))
        XCTAssertEqual(e.state.roundsWon, [3, 0])
    }

    func testTurnLimitDecidesByHealth() {
        var c = GameConfig()
        c.rules.maxShotsPerPlayerPerRound = 2
        var e = engine(config: c)
        e.submit(hit(e))  // player 0 damages player 1
        e.submit(dud)
        e.submit(dud)
        let r = e.submit(dud)
        XCTAssertEqual(r.events, [.roundOver(winner: 0, reason: .turnLimit)])
    }

    func testTossIsDeterministic() {
        let a = (0..<200).map { MatchSetup.tossWinner(seed: UInt64($0)) }
        XCTAssertEqual(a, (0..<200).map { MatchSetup.tossWinner(seed: UInt64($0)) })
        XCTAssertTrue(a.contains(0) && a.contains(1))
    }

    func testNearMissReported() {
        var e = engine()
        var input = hit(e)
        // Walk power down until the arrow lands short but close.
        var found = false
        for _ in 0..<200 {
            input.powerPermille -= 1
            let o = e.preview(input, recordPath: false)
            if o.hitArcher == nil, o.impact == .terrain,
               Hitbox.distance(from: o.point, feet: e.state.conditions.archerPosition(1),
                               scale: e.config.physics.archerScale) < 3 {
                found = true; break
            }
        }
        guard found else { return } // terrain/obstacle may make this seed unsuitable
        let r = e.submit(input)
        XCTAssertNotNil(r.nearMiss)
        XCTAssertLessThanOrEqual(r.nearMiss!, 3)
    }

    /// Wind (A6.6, revised): one direction for the whole match, the same for
    /// both players, a new strength only after an arrow strikes an archer, and
    /// always beatable from both sides.
    func testWindKeepsDirectionAndChangesOnlyAfterStrikes() {
        for m in 0..<6 {
            let seed = SplitMix64.hash(4242, UInt64(m))
            var engine = MatchEngine(setup: MatchSetup(seed: seed, arena: .hills, roundsToWin: 2, firstShooter: m % 2))
            var ais = [AIPlayer(difficulty: .medium, seed: seed &+ 1, search: .fast),
                       AIPlayer(difficulty: .hard, seed: seed &+ 2, search: .fast)]
            var sign: FloatingPointSign? = engine.state.windWorld == 0 ? nil : engine.state.windWorld.sign
            var shots = 0
            while !engine.state.isOver && shots < 400 {
                if case .roundOver = engine.state.phase { engine.startNextRound(); continue }
                let shooter = engine.state.currentShooter
                // Both players feel the same world wind.
                XCTAssertEqual(engine.state.conditions.windRelative * RoundConditions.facing(shooter), engine.state.windWorld)
                let before = engine.state.windWorld
                let report = engine.submit(ais[shooter].chooseShot(engine: engine))
                shots += 1
                let after = engine.state.windWorld
                if report.outcome.hitArcher == nil && engine.state.suddenDeath == 0 {
                    if case .awaitingShot = engine.state.phase { XCTAssertEqual(before, after, "wind changed without a strike") }
                }
                if after != 0 {
                    if sign == nil { sign = after.sign }
                    XCTAssertEqual(after.sign, sign, "wind flipped direction")
                }
                if case .awaitingShot = engine.state.phase {
                    var c = engine.state.conditions
                    for s in [0, 1] {
                        c.windRelative = engine.state.windWorld * RoundConditions.facing(s)
                        XCTAssertTrue(ShotSearch.isHittable(c, shooter: s, config: engine.config))
                    }
                }
            }
        }
    }

    /// A hit knocks the target back (more on harder settings), never past the
    /// cap, and both archers can always still hit each other.
    func testHitsKnockTheTargetBack() {
        for challenge in HitChallenge.allCases {
            var pushes = 0
            for m in 0..<4 {
                let seed = SplitMix64.hash(9090, UInt64(m))
                var engine = MatchEngine(setup: MatchSetup(seed: seed, arena: .hills, roundsToWin: 2, firstShooter: 0,
                                                           challenge: challenge))
                var ais = [AIPlayer(difficulty: .hard, seed: seed &+ 1, search: .fast),
                           AIPlayer(difficulty: .hard, seed: seed &+ 2, search: .fast)]
                var shots = 0
                while !engine.state.isOver && shots < 200 {
                    if case .roundOver = engine.state.phase {
                        engine.startNextRound()
                        XCTAssertEqual(engine.state.conditions.archerOffsets, [0, 0], "new round, back to the start")
                        continue
                    }
                    let before = engine.state.conditions.archerOffsets
                    let r = engine.submit(ais[engine.state.currentShooter].chooseShot(engine: engine))
                    shots += 1
                    for e in r.events {
                        guard case let .knockedBack(archer, offset) = e else { continue }
                        pushes += 1
                        XCTAssertEqual(archer, r.outcome.hitArcher)
                        let push = offset - before[archer]
                        XCTAssertGreaterThan(push, 0)
                        XCTAssertLessThanOrEqual(push, Double(challenge.knockbackTenths.upperBound) / 10 + 1e-9)
                        XCTAssertLessThanOrEqual(offset, challenge.maxKnockback + 1e-9)
                        XCTAssertEqual(engine.state.conditions.archerOffsets[archer], offset)
                    }
                    if case .awaitingShot = engine.state.phase {
                        var c = engine.state.conditions
                        for s in [0, 1] {
                            c.windRelative = engine.state.windWorld * RoundConditions.facing(s)
                            XCTAssertTrue(ShotSearch.isHittable(c, shooter: s, config: engine.config), "\(challenge)")
                        }
                    }
                }
            }
            XCTAssertGreaterThan(pushes, 0, "\(challenge): hits should knock archers back")
        }
    }
}
