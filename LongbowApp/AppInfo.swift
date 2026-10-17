import Foundation

/// The game's name is not final (spec A26.1): never hard-code it elsewhere.
enum AppInfo {
    static let displayName = "Longbow"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
