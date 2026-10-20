import Foundation

/// Device-local settings in `UserDefaults` (spec A2, A18).
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var soundOn: Bool { didSet { defaults.set(soundOn, forKey: "soundOn") } }
    @Published var musicOn: Bool { didSet { defaults.set(musicOn, forKey: "musicOn") } }
    @Published var hapticsOn: Bool { didSet { defaults.set(hapticsOn, forKey: "hapticsOn") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["soundOn": true, "musicOn": true, "hapticsOn": true])
        // One-time reset: an ambiguous pause-menu label left sound switched off
        // for some players, who then thought the game was silent.
        if !defaults.bool(forKey: "soundResetV1") {
            defaults.set(true, forKey: "soundOn")
            defaults.set(true, forKey: "soundResetV1")
        }
        soundOn = defaults.bool(forKey: "soundOn")
        musicOn = defaults.bool(forKey: "musicOn")
        hapticsOn = defaults.bool(forKey: "hapticsOn")
    }
}
