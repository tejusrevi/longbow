import Foundation

/// Repo-root `Shared/` folder: golden vectors live there so client and server
/// tests read the very same files.
let sharedDirectory: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // LongbowCoreTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // Core
    .deletingLastPathComponent() // repo root
    .appendingPathComponent("Shared")
