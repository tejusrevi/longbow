import XCTest
import LongbowCore

/// Milestone 1 acceptance: "no crash in 100 automated AI-vs-AI matches".
/// Run in release for speed: `swift test -c release --package-path Core`.
final class SoakTests: XCTestCase {
    func testHundredAIMatches() {
        var outcomes = [0, 0]
        var totalShots = 0
        let difficulties: [AIDifficulty] = [.easy, .medium, .hard]
        for i in 0..<100 {
            let seed = SplitMix64.hash(0xC0FFEE, UInt64(i))
            var engine = MatchEngine(setup: MatchSetup(
                seed: seed, arena: .hills, roundsToWin: 3, firstShooter: MatchSetup.tossWinner(seed: seed)))
            var ais = [
                AIPlayer(difficulty: difficulties[i % 3], seed: seed &+ 1, search: .fast),
                AIPlayer(difficulty: difficulties[(i + 1) % 3], seed: seed &+ 2, search: .fast),
            ]
            var guardCount = 0
            while !engine.state.isOver {
                guardCount += 1
                XCTAssertLessThan(guardCount, 1000, "match \(i) did not finish")
                if guardCount >= 1000 { break }
                if case .roundOver = engine.state.phase { engine.startNextRound(); continue }
                let shooter = engine.state.currentShooter
                let input = ais[shooter].chooseShot(engine: engine)
                let brace = ais[1 - shooter].braceMultiplier()
                let report = engine.submit(input, braceMultiplier: brace)
                ais[shooter].observe(report)
                totalShots += 1
                XCTAssertTrue(report.health.allSatisfy { (0...100).contains($0) })
            }
            if let w = engine.state.winner { outcomes[w] += 1 }
        }
        XCTAssertEqual(outcomes[0] + outcomes[1], 100)
        print("soak: wins \(outcomes), shots \(totalShots), avg \(Double(totalShots) / 100) shots/match")
    }
}
