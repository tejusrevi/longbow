import UIKit

/// Haptics (spec A16). Every meaningful moment in a match has a feel:
/// drawing, letting go, landings, hits, near misses, the last seconds of
/// the shot clock, and the end of rounds and matches.
protocol HapticsService: AnyObject {
    /// Finger down to start aiming.
    func grab()
    /// Every 5 % of draw power.
    func powerTick()
    /// Releasing the arrow.
    func release()
    /// An arrow thuds into the ground or an obstacle.
    func landed()
    /// An arrow lands close to you.
    func nearMiss()
    /// You took a hit.
    func tookHit()
    /// Headshot (either way).
    func headshot()
    /// Each of the last five seconds on the shot clock.
    func timerTick()
    func roundWon()
    func roundLost()
    /// Match won, level up, new hat.
    func success()
    /// Buttons, toggles, tabs.
    func selection()
    /// A small, light touch (a glance, a head turn, the top of an arrow's arc).
    func tap()
    /// Something arrives or appears (a round starts, a sign goes up).
    func bump()
    /// A chicken flapping: three quick light taps.
    func flutter()
    /// A solid knock.
    func thud()
}

final class DeviceHapticsService: HapticsService {
    private let settings: SettingsStore
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()
    private let select = UISelectionFeedbackGenerator()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private func run(_ body: () -> Void) {
        guard settings.hapticsOn else { return }
        body()
    }

    func grab() { run { soft.impactOccurred(intensity: 0.7) } }
    func powerTick() { run { light.impactOccurred(intensity: 0.55) } }
    func release() { run { rigid.impactOccurred(intensity: 0.9) } }
    func landed() { run { soft.impactOccurred(intensity: 0.5) } }
    func nearMiss() { run { medium.impactOccurred(intensity: 0.6) } }
    func tookHit() { run { heavy.impactOccurred() } }
    func headshot() { run { notify.notificationOccurred(.success) } }
    func timerTick() { run { rigid.impactOccurred(intensity: 0.5) } }
    func roundWon() { run { notify.notificationOccurred(.success) } }
    func roundLost() { run { notify.notificationOccurred(.warning) } }
    func success() { run { notify.notificationOccurred(.success) } }
    func selection() { run { select.selectionChanged() } }
    func tap() { run { light.impactOccurred(intensity: 0.45) } }
    func bump() { run { medium.impactOccurred(intensity: 0.75) } }
    func thud() { run { heavy.impactOccurred(intensity: 0.8) } }
    func flutter() {
        run {
            light.impactOccurred(intensity: 0.6)
            for (i, k) in [0.45, 0.35].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07 * Double(i + 1)) { [weak self] in
                    guard let self, self.settings.hapticsOn else { return }
                    self.light.impactOccurred(intensity: k)
                }
            }
        }
    }
}
