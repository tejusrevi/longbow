/// Finds a shot that lands on a target archer. Used by the AI and by round
/// generation, which only accepts conditions where a hit is possible.
///
/// For each launch angle it binary-searches the power so the arrow lands at
/// the target's x, which takes ~12 simulations per angle instead of a full
/// power sweep. Deterministic, so the server can run the same check.
public enum ShotSearch {
    public struct Result: Sendable {
        public var input: ShotInput
        /// The shot hits the target archer.
        public var hits: Bool
        /// The shot hits the aimed-for part.
        public var hitsAimedPart: Bool
        /// Distance from the landing point to the aim point (0 on a hit).
        public var miss: Double
    }

    public static func search(
        conditions: RoundConditions,
        shooter: Int,
        config: GameConfig,
        aimPart: BodyPart = .body,
        angleStepTenths: Int = 20,
        stopAtFirstHit: Bool = false
    ) -> Result {
        let target = 1 - shooter
        let dir = RoundConditions.facing(shooter)
        let aimPoint = Hitbox.center(of: aimPart, feet: conditions.archerPosition(target), scale: config.physics.archerScale)
        let aim = config.aim

        var best = Result(input: ShotInput(angleTenths: 450, powerPermille: 700), hits: false, hitsAimedPart: false,
                          miss: .infinity)

        func evaluate(_ input: ShotInput) -> (signed: Double, result: Result) {
            let o = ShotSimulator.simulate(input, shooter: shooter, conditions: conditions, config: config, recordPath: false)
            let hit = o.hitArcher == target
            let r = Result(input: input, hits: hit, hitsAimedPart: hit && o.hitPart == aimPart,
                           miss: hit ? 0 : (o.hitArcher == shooter ? 1e9 : o.point.distance(to: aimPoint)))
            if better(r, than: best) { best = r }
            return ((o.point.x - aimPoint.x) * dir, r)
        }

        // Try the most useful angles first so early exits are common.
        var angles: [Int] = []
        var a = aim.minAngleTenths
        while a <= aim.maxAngleTenths { angles.append(a); a += angleStepTenths }
        angles.sort { abs($0 - 400) < abs($1 - 400) }

        for angle in angles {
            var lo = 0, hi = 1000
            let far = evaluate(ShotInput(angleTenths: angle, powerPermille: hi))
            if stopAtFirstHit && best.hits { return best }
            if far.signed < 0 { continue } // can't reach at this angle
            for _ in 0..<11 {
                let mid = (lo + hi) / 2
                let e = evaluate(ShotInput(angleTenths: angle, powerPermille: mid))
                if best.hitsAimedPart || (stopAtFirstHit && best.hits) { return best }
                if e.signed < 0 { lo = mid } else { hi = mid }
                if hi - lo <= 1 { break }
            }
        }
        return best
    }

    /// Hits beat misses; the aimed part beats other parts; then closest.
    static func better(_ a: Result, than b: Result) -> Bool {
        if a.hitsAimedPart != b.hitsAimedPart { return a.hitsAimedPart }
        if a.hits != b.hits { return a.hits }
        return a.miss < b.miss
    }

    /// True when some shot from `shooter` can hit the other archer.
    public static func isHittable(_ conditions: RoundConditions, shooter: Int = 0, config: GameConfig) -> Bool {
        search(conditions: conditions, shooter: shooter, config: config, angleStepTenths: 30, stopAtFirstHit: true).hits
    }
}
