// swift-tools-version:5.9
// Core: pure Swift game logic. No UIKit, SpriteKit, network or monetization (spec A3).
import PackageDescription

let package = Package(
    name: "LongbowCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LongbowCore", targets: ["LongbowCore"]),
        .executable(name: "golden-gen", targets: ["GoldenGen"]),
    ],
    targets: [
        .target(name: "LongbowCore"),
        .executableTarget(name: "GoldenGen", dependencies: ["LongbowCore"]),
        .testTarget(
            name: "LongbowCoreTests",
            dependencies: ["LongbowCore"]
        ),
    ]
)
