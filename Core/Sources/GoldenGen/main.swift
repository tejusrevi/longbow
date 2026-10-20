// Regenerates Shared/golden_shots.json. Run from the repo root:
//   swift run --package-path Core golden-gen Shared/golden_shots.json
// Only regenerate when the physics contract changes on purpose; the server port
// must then be updated to match.
import Foundation
import LongbowCore

// Pass "-" as the shots path to leave golden_shots.json untouched.
let outPath = CommandLine.arguments.dropFirst().first ?? "golden_shots.json"
var rng = SplitMix64(seed: 0x10_6B0F)
var shots: [GoldenShot] = []
let config = GameConfig.default

for id in 0..<520 {
    let seed = rng.next()
    let shooter = id % 2
    let arena = ArenaProfile.ID.hills
    let conditions = RoundConditions.generate(seed: seed, arena: .profile(for: arena), physics: config.physics)
    let input: ShotInput
    if id % 3 == 0 {
        // Aimed shots so the file contains plenty of hits on every body part:
        // aim straight at the plainly generated conditions the test rebuilds.
        let best = ShotSearch.search(conditions: conditions, shooter: shooter, config: config,
                                     aimPart: id % 2 == 0 ? .head : .body).input
        let jitter = rng.nextInt(in: -3...3)
        input = ShotInput(angleTenths: best.angleTenths, powerPermille: best.powerPermille + jitter).clamped()
    } else {
        input = ShotInput(angleTenths: rng.nextInt(in: -100...850), powerPermille: rng.nextInt(in: 0...1000))
    }
    let o = ShotSimulator.simulate(input, shooter: shooter, conditions: conditions, config: config, recordPath: false)
    shots.append(GoldenShot(id: id, seed: seed, arena: arena, shooter: shooter, input: input, outcome: o))
}

let file = GoldenFile(
    version: 4,
    note: "Round seed + input -> exact impact. Conditions = RoundConditions.generate(seed, arena, default physics). Doubles as IEEE-754 bit patterns.",
    shots: shots
)
let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
if outPath != "-" { try enc.encode(file).write(to: URL(fileURLWithPath: outPath)) }
var counts: [String: Int] = [:]
for s in shots { counts[s.expected.impact + (s.expected.part.map { "/" + $0.rawValue } ?? ""), default: 0] += 1 }
print("wrote \(shots.count) shots to \(outPath): \(counts.sorted { $0.key < $1.key })")

// MARK: Match traces (Shared/golden_matches.json)
//
// Whole matches played by seeded AIs on every difficulty. The server's port of
// MatchEngine must replay each input sequence and reach exactly the same state
// after every turn: events, health, wind and knockback, as bit patterns.

func hex(_ d: Double) -> String { GoldenShot.hex(d.bitPattern) }

func eventCode(_ e: TurnReport.Event) -> String {
    switch e {
    case let .nextTurn(s, lb): return "nextTurn:\(s):\(lb)"
    case let .windChanged(w): return "windChanged:\(hex(w))"
    case let .knockedBack(a, off): return "knockedBack:\(a):\(hex(off))"
    case let .suddenDeath(p): return "suddenDeath:\(p)"
    case let .roundOver(w, r): return "roundOver:\(w):\(r.rawValue)"
    case let .matchOver(w): return "matchOver:\(w)"
    }
}

struct TraceTurn: Codable {
    var angleTenths: Int
    var powerPermille: Int
    var impact: String
    var xBits: String
    var damage: Int
    var health: [Int]
    var events: [String]
    var windBits: String
    var offsetBits: [String]
    var nextShooter: Int
    var round: Int
}

struct TraceMatch: Codable {
    var seed: String
    var challenge: String
    var firstShooter: Int
    var startWindBits: String
    var startDistance: Double
    var turns: [TraceTurn]
}

if CommandLine.arguments.count > 2 {
    var traces: [TraceMatch] = []
    var mrng = SplitMix64(seed: 0xD0E1)
    for m in 0..<18 {
        let seed = mrng.next()
        let challenge = HitChallenge.allCases[m % 3]
        let first = MatchSetup.tossWinner(seed: seed)
        var engine = MatchEngine(setup: MatchSetup(seed: seed, arena: .hills, roundsToWin: 2, firstShooter: first,
                                                   challenge: challenge))
        var ais = [AIPlayer(difficulty: AIDifficulty.allCases[m % 3], seed: seed &+ 1, search: .fast),
                   AIPlayer(difficulty: .hard, seed: seed &+ 2, search: .fast)]
        var trace = TraceMatch(seed: GoldenShot.hex(seed), challenge: challenge.rawValue, firstShooter: first,
                               startWindBits: hex(engine.state.windWorld),
                               startDistance: engine.state.conditions.distance, turns: [])
        while !engine.state.isOver && trace.turns.count < 300 {
            if case .roundOver = engine.state.phase { engine.startNextRound(); continue }
            let shooter = engine.state.currentShooter
            let input = ais[shooter].chooseShot(engine: engine)
            let r = engine.submit(input)
            ais[0].observe(r); ais[1].observe(r)
            let kind: String
            switch r.outcome.impact {
            case let .archer(i, p): kind = "archer:\(i):\(p.rawValue)"
            case .terrain: kind = "terrain"
            case let .obstacle(i): kind = "obstacle:\(i)"
            case .outOfBounds: kind = "outOfBounds"
            case .timeout: kind = "timeout"
            }
            trace.turns.append(TraceTurn(
                angleTenths: r.input.angleTenths, powerPermille: r.input.powerPermille, impact: kind,
                xBits: hex(r.outcome.point.x), damage: r.damage, health: r.health, events: r.events.map(eventCode),
                windBits: hex(engine.state.windWorld), offsetBits: engine.state.conditions.archerOffsets.map(hex),
                nextShooter: engine.state.currentShooter, round: engine.state.round))
        }
        traces.append(trace)
    }
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(traces).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("wrote \(traces.count) match traces, \(traces.map(\.turns.count).reduce(0, +)) turns")
}
