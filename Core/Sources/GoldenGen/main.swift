// Regenerates Shared/golden_shots.json. Run from the repo root:
//   swift run --package-path Core golden-gen Shared/golden_shots.json
// Only regenerate when the physics contract changes on purpose; the server port
// must then be updated to match.
import Foundation
import LongbowCore

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
        // Aimed shots so the file contains plenty of hits on every body part.
        let engine = MatchEngine(setup: MatchSetup(seed: seed, arena: arena, roundsToWin: 3, firstShooter: shooter))
        let ai = AIPlayer(difficulty: id % 2 == 0 ? .hard : .medium, seed: seed, search: .fast)
        let best = ai.bestShot(engine: engine)
        let jitter = rng.nextInt(in: -3...3)
        input = ShotInput(angleTenths: best.angleTenths, powerPermille: best.powerPermille + jitter).clamped()
        // The engine regenerates round-1 conditions from the match seed; use those.
        let o = ShotSimulator.simulate(input, shooter: shooter, conditions: engine.state.conditions, config: config, recordPath: false)
        shots.append(GoldenShot(id: id, seed: engine.state.conditions.seed, arena: arena, shooter: shooter, input: input, outcome: o))
        continue
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
try enc.encode(file).write(to: URL(fileURLWithPath: outPath))
var counts: [String: Int] = [:]
for s in shots { counts[s.expected.impact + (s.expected.part.map { "/" + $0.rawValue } ?? ""), default: 0] += 1 }
print("wrote \(shots.count) shots to \(outPath): \(counts.sorted { $0.key < $1.key })")
