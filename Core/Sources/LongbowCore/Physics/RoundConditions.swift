/// Conditions for one round (or one sudden-death pair), generated from a seed
/// (spec A6.6). Never changes between the two players' shots.
public struct RoundConditions: Codable, Equatable, Sendable {
    public var seed: UInt64
    public var arena: ArenaProfile.ID
    public var distance: Double
    /// Wind relative to the shooter: positive = tailwind (toward the opponent).
    /// Mirrored, so both players get exactly the same wind for their own shots.
    public var windRelative: Double
    public var gravity: Double
    public var terrain: Terrain
    public var obstacles: [Obstacle]

    /// Feet position of archer 0 (left, facing right) and 1 (right, facing left).
    public func archerPosition(_ index: Int) -> Vec2 {
        index == 0 ? Vec2(0, 0) : Vec2(distance, 0)
    }

    /// +1 for the left archer (shoots right), −1 for the right archer.
    public static func facing(_ index: Int) -> Double { index == 0 ? 1 : -1 }

    public static func roundSeed(matchSeed: UInt64, round: Int, suddenDeath: Int = 0) -> UInt64 {
        SplitMix64.hash(matchSeed, UInt64(round), UInt64(suddenDeath))
    }

    /// Like `generate`, but only returns conditions where a hit is possible
    /// (no unbeatable wind, no wall of hill). Tries derived seeds until one
    /// works; as a last resort, calms the wind and clears obstacles.
    public static func generatePlayable(seed: UInt64, arena: ArenaProfile, config: GameConfig) -> RoundConditions {
        var last = generate(seed: seed, arena: arena, physics: config.physics)
        if ShotSearch.isHittable(last, config: config) { return last }
        for attempt in 1...12 {
            last = generate(seed: SplitMix64.hash(seed, 0xF1, UInt64(attempt)), arena: arena, physics: config.physics)
            if ShotSearch.isHittable(last, config: config) { return last }
        }
        last.windRelative = 0
        last.obstacles = []
        return last
    }

    /// Wind for the n-th pair of shots in a round (pair 0 = the round's own
    /// wind). Each pair the wind *drifts* a little from the last one — half a
    /// step, sometimes a whole one — so the previous trajectory never quite
    /// works again, but the wind never jumps wildly. Both players share each
    /// pair's wind (A6.6 fairness). Never drifts into an unhittable wind.
    public func playableWind(forPair pair: Int, arena: ArenaProfile, config: GameConfig) -> Double {
        guard pair > 0 else { return windRelative }
        var wind = windRelative
        for p in 1...pair { wind = driftedWind(from: wind, pair: p, arena: arena, config: config) }
        return wind
    }

    /// One drift step: the wind for `pair`, given the previous pair's wind.
    public func driftedWind(from wind: Double, pair: Int, arena: ArenaProfile, config: GameConfig) -> Double {
        var rng = SplitMix64(seed: SplitMix64.hash(seed, 0x57, UInt64(pair)))
        let size: Double = rng.nextInt(in: 0...3) == 0 ? 1.0 : 0.5
        var sign: Double = rng.nextBool() ? 1 : -1
        // Lean back toward the middle near the limits.
        if abs(wind + sign * size) > arena.maxWind { sign = -sign }
        var probe = self
        for candidate in [wind + sign * size, wind - sign * size] {
            probe.windRelative = candidate
            if ShotSearch.isHittable(probe, config: config) { return candidate }
        }
        return wind
    }

    public static func generate(seed: UInt64, arena: ArenaProfile, physics: PhysicsConfig) -> RoundConditions {
        var rng = SplitMix64(seed: seed)
        let distance = Double(rng.nextInt(in: arena.distanceRange))

        let minSteps = Int(arena.minWind * 2)
        let maxSteps = Int(arena.maxWind * 2)
        let windStrength = Double(rng.nextInt(in: minSteps...maxSteps)) * 0.5
        let windSign: Double = rng.nextBool() ? 1 : -1

        var waves: [Terrain.Wave] = []
        let wavelengthRanges: [(Double, Double)] = [(distance * 0.5, distance * 1.1), (40, 90), (12, 28)]
        for (i, amp) in arena.waveAmplitudes.enumerated() {
            let range = wavelengthRanges[min(i, wavelengthRanges.count - 1)]
            waves.append(Terrain.Wave(
                amplitude: amp * rng.nextDouble(0.4, 1.0),
                wavelength: rng.nextDouble(range.0, range.1),
                phaseDegrees: Double(rng.nextInt(in: 0...359))
            ))
        }
        let valley = rng.nextDouble(0, arena.maxValleyDepth)
        let terrain = Terrain(distance: distance, waves: waves, valleyDepth: valley)

        var obstacles: [Obstacle] = []
        let count = arena.obstacleKinds.isEmpty ? 0 : rng.nextInt(in: 0...arena.maxObstacles)
        if count > 0 {
            let kind = arena.obstacleKinds[rng.nextInt(in: 0...(arena.obstacleKinds.count - 1))]
            if count == 1 {
                let x = distance * 0.5
                obstacles.append(.make(kind, at: x, baseY: terrain.height(at: x)))
            } else {
                // Mirrored pair (A6.6): x and distance − x.
                let x = (distance * rng.nextDouble(0.25, 0.42)).rounded()
                obstacles.append(.make(kind, at: x, baseY: terrain.height(at: x)))
                obstacles.append(.make(kind, at: distance - x, baseY: terrain.height(at: distance - x)))
            }
        }

        return RoundConditions(
            seed: seed, arena: arena.id, distance: distance,
            windRelative: windStrength * windSign,
            gravity: arena.gravity ?? physics.gravity,
            terrain: terrain, obstacles: obstacles
        )
    }
}
