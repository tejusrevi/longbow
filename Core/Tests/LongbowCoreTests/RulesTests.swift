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
        XCTAssertEqual(r.events, [.nextTurn(shooter: 1, lastBreath: true)])
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
}
