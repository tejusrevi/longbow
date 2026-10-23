import Foundation
import LongbowCore

/// Remote config + feature flags (spec A23). Milestone 1 ships the bundled
/// defaults only; the Nakama-backed implementation arrives in Milestone 2.
protocol RemoteConfigService: AnyObject {
    var config: AppConfig { get }
    func refresh() async
}

struct AppConfig: Codable {
    var game: GameConfig
    var camera: CameraConfig
    var flags: FeatureFlags
    var xp: XPConfig
    var monetization: MonetizationFlags
    var minimumAppVersion: String

    static func loadBundled() -> AppConfig {
        guard let url = Bundle.main.url(forResource: "DefaultConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            assertionFailure("DefaultConfig.json missing or invalid")
            return AppConfig(game: .default, camera: .init(), flags: .init(), xp: .init(),
                             monetization: .init(), minimumAppVersion: "1.0.0")
        }
        return config
    }
}

struct CameraConfig: Codable {
    /// World width (m) visible while aiming.
    var aimViewWidth: Double = 26
    var flightMaxViewWidth: Double = 120
    var impactViewWidth: Double = 28
    var followSmoothing: Double = 0.45
    var impactHoldSeconds: Double = 1.4
    var panSeconds: Double = 1.6
    var openingPanSeconds: Double = 2.8
}

struct FeatureFlags: Codable {
    var dailyShotEnabled = true
    var quickMatchEnabled = true
    var asyncMatchesEnabled = true
    var leaguesEnabled = true
    var braceEnabled = true
    var lineBoilEnabled = true
    var rankedEnabled = false
    var appClipInvitesEnabled = false
    var liveAimPreviewEnabled = false
    var allowAsymmetricMaps = false
}

struct XPConfig: Codable {
    var matchCompleted = 20
    var matchWon = 30
    var headshot = 5
}

/// PART B flags. All false in v1.0; the master switch gates the rest (B2.1).
struct MonetizationFlags: Codable {
    var enabled = false
    var shopEnabled = false
    var iapEnabled = false
    var seasonPassEnabled = false
    var rewardedAdsEnabled = false
    var premiumAccentEnabled = false
    var paidNameChangeEnabled = false
    var streakProtectionEnabled = false
}

final class BundledRemoteConfigService: RemoteConfigService {
    private(set) var config: AppConfig = .loadBundled()

    func refresh() async {
        // Milestone 2: fetch `getConfig` from the server and cache it.
    }
}
