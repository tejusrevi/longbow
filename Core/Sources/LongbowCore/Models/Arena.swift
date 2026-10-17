/// Physics and generation profile for an arena (spec A13).
public struct ArenaProfile: Codable, Equatable, Sendable {
    public enum ID: String, Codable, CaseIterable, Sendable {
        case hills, castle, windmills, moon
    }

    public var id: ID
    /// nil = use `PhysicsConfig.gravity`.
    public var gravity: Double?
    public var distanceRange: ClosedRange<Int>
    /// Max wind in m/s²; rounded to 0.5 steps.
    public var maxWind: Double
    public var minWind: Double
    /// Amplitudes (m) of the three terrain waves, largest first.
    public var waveAmplitudes: [Double]
    public var maxValleyDepth: Double
    public var obstacleKinds: [Obstacle.Kind]
    public var maxObstacles: Int

    public static let hills = ArenaProfile(
        id: .hills, gravity: nil, distanceRange: 150...350,
        maxWind: 3, minWind: 0,
        waveAmplitudes: [7, 3, 1.2], maxValleyDepth: 12,
        obstacleKinds: [.tree, .rock], maxObstacles: 2
    )

    public static func profile(for id: ID) -> ArenaProfile {
        switch id {
        // Castle, Windmills and Moon arrive in Milestone 3; until then they use the
        // Hills profile with their own physics tweaks.
        case .hills: return .hills
        case .castle:
            var p = ArenaProfile.hills
            p.id = .castle
            return p
        case .windmills:
            var p = ArenaProfile.hills
            p.id = .windmills
            p.minWind = 3
            p.maxWind = 10
            return p
        case .moon:
            var p = ArenaProfile.hills
            p.id = .moon
            p.gravity = 1.6
            p.minWind = 0
            p.maxWind = 0
            p.distanceRange = 300...600
            p.obstacleKinds = [.rock]
            return p
        }
    }
}
