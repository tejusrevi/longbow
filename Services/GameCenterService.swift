import GameKit
import UIKit

/// Game Center sign-in (A7.1). Optional: if the player is signed in to Game
/// Center, their Longbow account follows them to a new phone or an iPad;
/// if not, the device account works exactly as before.
@MainActor
final class GameCenterAuth {
    static let shared = GameCenterAuth()

    /// What the server needs to check with Apple that this is really the player.
    struct Identity {
        let playerId: String
        let bundleId: String
        let publicKeyURL: URL
        let signature: Data
        let salt: Data
        let timestamp: UInt64

        var json: [String: Any] {
            ["player_id": playerId, "bundle_id": bundleId, "timestamp_seconds": timestamp,
             "salt": salt.base64EncodedString(), "signature": signature.base64EncodedString(),
             "public_key_url": publicKeyURL.absoluteString]
        }
    }

    private var started = false
    /// The first sign-in attempt has finished (either way).
    private var settled = false

    var isAuthenticated: Bool { GKLocalPlayer.local.isAuthenticated }

    /// Starts sign-in once. GameKit shows its own welcome banner, or its
    /// sign-in sheet if the player isn't signed in on this device yet.
    func start() {
        guard !started else { return }
        started = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                #if DEBUG
                print("GC handler: vc=\(viewController != nil) authenticated=\(GKLocalPlayer.local.isAuthenticated) error=\(String(describing: error))")
                #endif
                if let viewController {
                    Self.topViewController()?.present(viewController, animated: true)
                    return
                }
                self.settled = true
            }
        }
    }

    /// Waits (briefly) for the first sign-in attempt to finish, then returns
    /// a fresh identity proof, or nil when Game Center isn't available.
    func identity() async -> Identity? {
        guard started else { return nil }
        for _ in 0..<40 {
            if settled { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard isAuthenticated, let bundleId = Bundle.main.bundleIdentifier else { return nil }
        do {
            let (url, signature, salt, timestamp) = try await GKLocalPlayer.local.fetchItemsForIdentityVerificationSignature()
            return Identity(playerId: GKLocalPlayer.local.teamPlayerID, bundleId: bundleId, publicKeyURL: url,
                            signature: signature, salt: salt, timestamp: timestamp)
        } catch {
            #if DEBUG
            print("GC identity failed: \(error)")
            #endif
            return nil
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
