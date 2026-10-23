import UIKit
import UserNotifications

/// Push notifications (A7.4): "Sam joined your duel. Tap to play."
/// Permission is asked only when you start a friend duel, the one moment it
/// obviously helps. Tapping a notification opens your waiting duel.
@MainActor
final class PushService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushService()

    /// A duel to jump back into (from a tapped notification).
    @Published var pendingMatchId: String?
    var pendingCode = ""
    var client: NakamaClient?
    private var token: String?

    /// Asks once (iOS remembers the answer), then registers with Apple.
    func requestIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                if granted { UIApplication.shared.registerForRemoteNotifications() }
            case .authorized, .provisional, .ephemeral:
                UIApplication.shared.registerForRemoteNotifications()
            default:
                break
            }
        }
    }

    /// At launch: if the player already allowed notifications, refresh the token.
    func registerIfAllowed() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task {
            if await center.notificationSettings().authorizationStatus == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        Task { _ = try? await client?.rpc("register_push", ["token": hex, "sandbox": Self.usesSandbox]) }
    }

    /// Development-signed builds (Xcode, the phone on your desk) talk to
    /// Apple's sandbox push service; App Store and TestFlight builds don't.
    static let usesSandbox: Bool = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let key = text.range(of: "<key>aps-environment</key>") else { return false }
        let rest = text[key.upperBound...]
        guard let open = rest.range(of: "<string>"), let close = rest.range(of: "</string>") else { return false }
        return rest[open.upperBound..<close.lowerBound] == "development"
    }()

    // MARK: UNUserNotificationCenterDelegate

    /// In the app already: no banner; the lobby shows the friend arriving.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let id = info["matchId"] as? String, code = info["code"] as? String ?? ""
        await MainActor.run {
            self.pendingCode = code
            self.pendingMatchId = id
        }
    }
}

/// Hands APNs callbacks to `PushService` (SwiftUI apps still get them here).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = PushService.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushService.shared.didRegister(deviceToken: deviceToken) }
    }
}
