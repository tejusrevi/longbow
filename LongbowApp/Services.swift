import SwiftUI

/// Dependency container (spec A3). Game and UI code only see the protocols.
final class Services {
    let settings: SettingsStore
    let progress: ProgressStore
    let remoteConfig: RemoteConfigService
    let audio: AudioService
    let haptics: HapticsService
    let analytics: AnalyticsService
    let monetization: MonetizationService
    /// The game server (friend duels and, later, accounts and leagues).
    @MainActor lazy var online: NakamaClient = .live()

    init(
        settings: SettingsStore,
        progress: ProgressStore,
        remoteConfig: RemoteConfigService,
        audio: AudioService,
        haptics: HapticsService,
        analytics: AnalyticsService,
        monetization: MonetizationService
    ) {
        self.settings = settings
        self.progress = progress
        self.remoteConfig = remoteConfig
        self.audio = audio
        self.haptics = haptics
        self.analytics = analytics
        self.monetization = monetization
    }

    static func live() -> Services {
        let settings = SettingsStore()
        return Services(
            settings: settings,
            progress: ProgressStore(),
            remoteConfig: BundledRemoteConfigService(),
            audio: DeviceAudioService(settings: settings),
            haptics: DeviceHapticsService(settings: settings),
            analytics: LocalAnalyticsService(),
            // PART B: pick LiveMonetizationService when MONETIZATION_COMPILED
            // is set and `monetization.enabled` is true.
            monetization: NoOpMonetizationService()
        )
    }

    var config: AppConfig { remoteConfig.config }
}

private struct ServicesKey: EnvironmentKey {
    static let defaultValue: Services = .live()
}

extension EnvironmentValues {
    var services: Services {
        get { self[ServicesKey.self] }
        set { self[ServicesKey.self] = newValue }
    }
}
