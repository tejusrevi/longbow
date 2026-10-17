/// Quantised shot input (spec A6.2). These integers are what is simulated and
/// what is sent to the server.
public struct ShotInput: Codable, Equatable, Hashable, Sendable {
    /// Angle above horizontal, facing the opponent, in tenths of a degree (−100...850).
    public var angleTenths: Int
    /// Power in permille (0...1000).
    public var powerPermille: Int

    public init(angleTenths: Int, powerPermille: Int) {
        self.angleTenths = angleTenths
        self.powerPermille = powerPermille
    }

    public func clamped(_ aim: AimConfig = .init()) -> ShotInput {
        ShotInput(
            angleTenths: min(max(angleTenths, aim.minAngleTenths), aim.maxAngleTenths),
            powerPermille: min(max(powerPermille, 0), 1000)
        )
    }

    /// Quantises a continuous angle (degrees) and power (0...1).
    public static func quantise(angleDegrees: Double, power: Double, aim: AimConfig = .init()) -> ShotInput {
        ShotInput(
            angleTenths: Int((angleDegrees * 10).rounded()),
            powerPermille: Int((power * 1000).rounded())
        ).clamped(aim)
    }

    public var angleDegrees: Double { Double(angleTenths) / 10 }
    public var power: Double { Double(powerPermille) / 1000 }
}

public enum BodyPart: String, Codable, Sendable, CaseIterable {
    case head, body, legs
}

/// Hitboxes per archer, relative to the feet (spec A6.4), multiplied by
/// `PhysicsConfig.archerScale`. Order = check order.
public enum Hitbox {
    public static func shapes(feet: Vec2, scale s: Double = 1) -> [(BodyPart, HitShape)] {
        [
            // Matches the drawing: the head art is scaled up 1.18× at the neck.
            (.head, .circle(center: Vec2(feet.x, feet.y + 1.68 * s), radius: 0.33 * s)),
            (.body, .rect(min: Vec2(feet.x - 0.3 * s, feet.y + 0.85 * s), max: Vec2(feet.x + 0.3 * s, feet.y + 1.5 * s))),
            (.legs, .rect(min: Vec2(feet.x - 0.22 * s, feet.y), max: Vec2(feet.x + 0.22 * s, feet.y + 0.85 * s))),
        ]
    }

    public static func center(of part: BodyPart, feet: Vec2, scale s: Double = 1) -> Vec2 {
        switch part {
        case .head: return Vec2(feet.x, feet.y + 1.68 * s)
        case .body: return Vec2(feet.x, feet.y + 1.2 * s)
        case .legs: return Vec2(feet.x, feet.y + 0.45 * s)
        }
    }

    /// Distance from a point to the nearest hitbox of an archer.
    public static func distance(from p: Vec2, feet: Vec2, scale: Double = 1) -> Double {
        shapes(feet: feet, scale: scale).map { $0.1.distance(to: p) }.min() ?? .infinity
    }
}

public struct ShotOutcome: Codable, Equatable, Sendable {
    public enum Impact: Codable, Equatable, Sendable {
        case archer(index: Int, part: BodyPart)
        case terrain
        case obstacle(index: Int)
        case outOfBounds
        case timeout
    }

    public var impact: Impact
    /// Where the arrow stopped (entry point for hits).
    public var point: Vec2
    /// Arrow velocity at impact (used for the stuck arrow's angle).
    public var velocity: Vec2
    /// Number of simulation steps until impact.
    public var steps: Int
    /// Positions at every step, starting at the launch point. Empty when not recorded.
    public var path: [Vec2]

    public var hitPart: BodyPart? {
        if case let .archer(_, part) = impact { return part }
        return nil
    }

    public var hitArcher: Int? {
        if case let .archer(index, _) = impact { return index }
        return nil
    }

    public func flightSeconds(stepsPerSecond: Int) -> Double {
        Double(steps) / Double(stepsPerSecond)
    }
}

/// Deterministic projectile simulation (spec A6.3).
///
/// Rules: fixed timestep, Double only, lookup-table trig, basic arithmetic in a
/// fixed order. The TypeScript server port must reproduce `Shared/golden_shots.json`.
public enum ShotSimulator {
    public static func simulate(
        _ rawInput: ShotInput,
        shooter: Int,
        conditions: RoundConditions,
        config: GameConfig = .default,
        recordPath: Bool = true
    ) -> ShotOutcome {
        let input = rawInput.clamped(config.aim)
        let phys = config.physics
        let dir = RoundConditions.facing(shooter)
        let dt = 1.0 / Double(phys.stepsPerSecond)
        let maxSteps = Int(phys.maxFlightSeconds * Double(phys.stepsPerSecond))

        let v0 = phys.minSpeed + input.power * (phys.maxSpeed - phys.minSpeed)
        var vx = dir * (v0 * Trig.cos(tenths: input.angleTenths))
        var vy = v0 * Trig.sin(tenths: input.angleTenths)
        let windAx = dir * conditions.windRelative
        let drag = phys.drag
        let g = conditions.gravity

        let feet = conditions.archerPosition(shooter)
        let scale = phys.archerScale
        var pos = Vec2(feet.x + dir * (phys.launchOffsetX * scale), feet.y + phys.launchOffsetY * scale)

        let target = 1 - shooter
        // Target first, then the shooter (an arrow can come back on a strong headwind).
        let archerShapes: [(Int, [(BodyPart, HitShape)])] = [
            (target, Hitbox.shapes(feet: conditions.archerPosition(target), scale: scale)),
            (shooter, Hitbox.shapes(feet: feet, scale: scale)),
        ]
        let minX = -phys.boundsMarginX
        let maxX = conditions.distance + phys.boundsMarginX
        let minY = phys.boundsBottom

        var path: [Vec2] = []
        if recordPath { path.reserveCapacity(min(maxSteps, 1500) + 1); path.append(pos) }

        var step = 0
        while step < maxSteps {
            step += 1
            let speed = (vx * vx + vy * vy).squareRoot()
            let ax = windAx - drag * vx * speed
            let ay = -g - drag * vy * speed
            vx = vx + ax * dt
            vy = vy + ay * dt
            let prev = pos
            pos = Vec2(prev.x + vx * dt, prev.y + vy * dt)

            // 1. Archers (head before body before legs).
            for (index, shapes) in archerShapes {
                for (part, shape) in shapes {
                    if let t = shape.entry(from: prev, to: pos) {
                        let hit = prev + (pos - prev) * t
                        if recordPath { path.append(hit) }
                        return ShotOutcome(impact: .archer(index: index, part: part), point: hit,
                                           velocity: Vec2(vx, vy), steps: step, path: path)
                    }
                }
            }
            // 2. Obstacles.
            for (index, obstacle) in conditions.obstacles.enumerated() {
                for shape in obstacle.shapes {
                    if let t = shape.entry(from: prev, to: pos) {
                        let hit = prev + (pos - prev) * t
                        if recordPath { path.append(hit) }
                        return ShotOutcome(impact: .obstacle(index: index), point: hit,
                                           velocity: Vec2(vx, vy), steps: step, path: path)
                    }
                }
            }
            // 3. Terrain: refine the crossing with a fixed 12-step bisection.
            if pos.y <= conditions.terrain.height(at: pos.x) {
                var lo = 0.0
                var hi = 1.0
                for _ in 0..<12 {
                    let mid = (lo + hi) * 0.5
                    let p = prev + (pos - prev) * mid
                    if p.y <= conditions.terrain.height(at: p.x) { hi = mid } else { lo = mid }
                }
                let hit = prev + (pos - prev) * hi
                if recordPath { path.append(hit) }
                return ShotOutcome(impact: .terrain, point: hit, velocity: Vec2(vx, vy), steps: step, path: path)
            }
            // 4. Bounds.
            if pos.x < minX || pos.x > maxX || pos.y < minY {
                if recordPath { path.append(pos) }
                return ShotOutcome(impact: .outOfBounds, point: pos, velocity: Vec2(vx, vy), steps: step, path: path)
            }
            if recordPath { path.append(pos) }
        }
        return ShotOutcome(impact: .timeout, point: pos, velocity: Vec2(vx, vy), steps: step, path: path)
    }
}
