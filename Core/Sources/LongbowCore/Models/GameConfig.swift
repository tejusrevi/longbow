/// Every tunable number the game uses (spec A3: "all tunable numbers come from
/// RemoteConfigService, with bundled defaults in DefaultConfig.json").
///
/// The Swift defaults below mirror `DefaultConfig.json` and are what Core tests
/// and golden vectors use. Physics values are part of the deterministic contract:
/// changing them changes every golden vector.
public struct GameConfig: Codable, Equatable, Sendable {
    public var physics: PhysicsConfig = .init()
    public var damage: DamageConfig = .init()
    public var rules: RulesConfig = .init()
    public var aim: AimConfig = .init()

    public init() {}

    public static let `default` = GameConfig()
}

public struct PhysicsConfig: Codable, Equatable, Sendable {
    public var minSpeed: Double = 20
    public var maxSpeed: Double = 75
    /// Light air drag: arrows carry, and 45° is (very nearly) the longest shot.
    public var drag: Double = 0.00015
    public var gravity: Double = 9.8
    /// Simulation steps per second (fixed timestep 1/120 s).
    public var stepsPerSecond: Int = 120
    public var maxFlightSeconds: Double = 18
    /// World bounds beyond the archers, in metres. Wider than the longest
    /// possible shot, so every arrow flies until it lands.
    public var boundsMarginX: Double = 800
    public var boundsBottom: Double = -20
    /// Size of the archers relative to the A6.4 hitboxes (1.0). Bigger archers are
    /// easier to hit; the art scales with it.
    public var archerScale: Double = 2.0
    /// Where the arrow leaves the bow, relative to the shooter's feet (x is along
    /// facing), at archer scale 1.
    public var launchOffsetX: Double = 0.35
    public var launchOffsetY: Double = 1.35
    /// An arrow landing within this distance of the target counts as a near miss.
    public var nearMissDistance: Double = 3

    public init() {}
}

public struct DamageConfig: Codable, Equatable, Sendable {
    public var head: Int = 50
    public var body: Int = 25
    public var legs: Int = 15
    public var startHealth: Int = 100

    public init() {}
}

public struct RulesConfig: Codable, Equatable, Sendable {
    public var roundsToWin: Int = 1
    public var roundsToWinEasyAI: Int = 1
    public var maxShotsPerPlayerPerRound: Int = 20
    public var shotTimeLimitSeconds: Double = 20

    public init() {}
}

public struct AimConfig: Codable, Equatable, Sendable {
    public var minAngleTenths: Int = -100
    public var maxAngleTenths: Int = 850
    /// Drag length for full power, as a fraction of screen height.
    public var maxDragFractionOfScreenHeight: Double = 0.4
    /// Releasing inside this radius (points) cancels the shot.
    public var deadZonePoints: Double = 12
    /// Share of the trajectory shown by the aim guide, 0...100.
    public var aimGuidePercent: Double = 15

    public init() {}
}
