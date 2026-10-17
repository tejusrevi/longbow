import Foundation
import XCTest
import LongbowCore

final class PhysicsTests: XCTestCase {
    func testTrigTablesMatchSharedFile() throws {
        struct Tables: Decodable { var sinBits: [String]; var cosBits: [String] }
        let data = try Data(contentsOf: sharedDirectory.appendingPathComponent("trig_tables.json"))
        let t = try JSONDecoder().decode(Tables.self, from: data)
        XCTAssertEqual(t.sinBits.count, 3601)
        for i in stride(from: 0, to: 3601, by: 1) {
            XCTAssertEqual(UInt64(t.sinBits[i].dropFirst(2), radix: 16), Trig.sinTable[i].bitPattern, "sin \(i)")
            XCTAssertEqual(UInt64(t.cosBits[i].dropFirst(2), radix: 16), Trig.cosTable[i].bitPattern, "cos \(i)")
        }
        XCTAssertEqual(Trig.sin(tenths: 900), 1)
        XCTAssertEqual(Trig.cos(tenths: 0), 1)
        XCTAssertEqual(Trig.sin(tenths: -100), Trig.sin(tenths: 3500))
    }

    func testGoldenShots() throws {
        let data = try Data(contentsOf: sharedDirectory.appendingPathComponent("golden_shots.json"))
        let file = try JSONDecoder().decode(GoldenFile.self, from: data)
        XCTAssertGreaterThanOrEqual(file.shots.count, 500)
        var mismatches = 0
        for shot in file.shots {
            let conditions = RoundConditions.generate(seed: shot.seedValue, arena: .profile(for: shot.arena),
                                                      physics: GameConfig.default.physics)
            let o = ShotSimulator.simulate(shot.input, shooter: shot.shooter, conditions: conditions, recordPath: false)
            let got = GoldenShot.expected(for: o)
            if got != shot.expected {
                mismatches += 1
                if mismatches < 5 { XCTFail("golden \(shot.id): expected \(shot.expected), got \(got)") }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    func testRecordedPathMatchesUnrecordedOutcome() {
        let c = RoundConditions.generate(seed: 99, arena: .hills, physics: .init())
        let input = ShotInput(angleTenths: 420, powerPermille: 810)
        let a = ShotSimulator.simulate(input, shooter: 0, conditions: c, recordPath: true)
        let b = ShotSimulator.simulate(input, shooter: 0, conditions: c, recordPath: false)
        XCTAssertEqual(a.point, b.point)
        XCTAssertEqual(a.steps, b.steps)
        XCTAssertEqual(a.path.count, a.steps + 1)
        XCTAssertEqual(a.path.last, a.point)
    }

    func testTerrainIsMirrorSymmetricWithFlatPads() {
        for seed in UInt64(1)...50 {
            let c = RoundConditions.generate(seed: seed, arena: .hills, physics: .init())
            let t = c.terrain
            XCTAssertEqual(t.height(at: 0), 0)
            XCTAssertEqual(t.height(at: 1.9), 0)
            XCTAssertEqual(t.height(at: c.distance - 1.5), 0)
            for x in stride(from: -50.0, through: c.distance + 50, by: 3.7) {
                XCTAssertEqual(t.height(at: x), t.height(at: c.distance - x), accuracy: 1e-9)
            }
            XCTAssertTrue((150...350).contains(c.distance))
            XCTAssertLessThanOrEqual(abs(c.windRelative), 3)
            XCTAssertEqual((c.windRelative * 2).rounded(), c.windRelative * 2)
            if c.obstacles.count == 2 {
                XCTAssertEqual(c.obstacles[0].x, c.distance - c.obstacles[1].x)
            }
        }
    }

    func testMirroredFairness() {
        // The same input from either side lands in the mirrored spot.
        for seed in UInt64(1)...30 {
            let c = RoundConditions.generate(seed: seed, arena: .hills, physics: .init())
            let input = ShotInput(angleTenths: 300 + Int(seed) * 7, powerPermille: 500 + Int(seed) * 13)
            let left = ShotSimulator.simulate(input, shooter: 0, conditions: c, recordPath: false)
            let right = ShotSimulator.simulate(input, shooter: 1, conditions: c, recordPath: false)
            XCTAssertEqual(left.point.x, c.distance - right.point.x, accuracy: 1e-6)
            XCTAssertEqual(left.point.y, right.point.y, accuracy: 1e-6)
        }
    }

    func testSegmentShapes() {
        let circle = HitShape.circle(center: Vec2(0, 0), radius: 1)
        XCTAssertEqual(circle.entry(from: Vec2(-3, 0), to: Vec2(3, 0))!, 1.0 / 3.0, accuracy: 1e-12)
        XCTAssertNil(circle.entry(from: Vec2(-3, 2), to: Vec2(3, 2)))
        let rect = HitShape.rect(min: Vec2(0, 0), max: Vec2(1, 1))
        XCTAssertEqual(rect.entry(from: Vec2(-1, 0.5), to: Vec2(3, 0.5))!, 0.25, accuracy: 1e-12)
        XCTAssertNil(rect.entry(from: Vec2(-1, 2), to: Vec2(3, 2)))
        // Fast arrows never tunnel: a segment crossing the whole box still hits.
        XCTAssertNotNil(rect.entry(from: Vec2(-10, 0.5), to: Vec2(10, 0.5)))
    }

    func testQuantise() {
        let q = ShotInput.quantise(angleDegrees: 38.24, power: 0.7806)
        XCTAssertEqual(q, ShotInput(angleTenths: 382, powerPermille: 781))
        XCTAssertEqual(ShotInput.quantise(angleDegrees: 120, power: 2), ShotInput(angleTenths: 850, powerPermille: 1000))
        XCTAssertEqual(ShotInput.quantise(angleDegrees: -40, power: -1), ShotInput(angleTenths: -100, powerPermille: 0))
    }

    func testFortyFiveDegreesGoesFurthest() {
        // Flat, windless, obstacle-free field: range should peak near 45°.
        var c = RoundConditions.generate(seed: 3, arena: .hills, physics: .init())
        c.terrain = Terrain(distance: 2000, waves: [], valleyDepth: 0)
        c.distance = 2000
        c.windRelative = 0
        c.obstacles = []
        func range(_ deg: Int) -> Double {
            ShotSimulator.simulate(ShotInput(angleTenths: deg * 10, powerPermille: 1000), shooter: 0, conditions: c,
                                   recordPath: false).point.x
        }
        let best = stride(from: 20, through: 70, by: 1).max { range($0) < range($1) }!
        XCTAssertTrue((42...46).contains(best), "longest shot at \(best)°")
    }

    func testEveryGeneratedRoundIsHittable() {
        let cfg = GameConfig.default
        for i in 0..<60 {
            let c = RoundConditions.generatePlayable(seed: SplitMix64.hash(77, UInt64(i)), arena: .hills, config: cfg)
            XCTAssertTrue(ShotSearch.isHittable(c, shooter: 0, config: cfg), "seed \(i)")
            XCTAssertTrue(ShotSearch.isHittable(c, shooter: 1, config: cfg), "seed \(i) (right side)")
            for pair in 1...4 {
                var p = c
                p.windRelative = c.playableWind(forPair: pair, arena: .hills, config: cfg)
                XCTAssertTrue(ShotSearch.isHittable(p, shooter: 0, config: cfg), "seed \(i) pair \(pair)")
            }
        }
    }
}
