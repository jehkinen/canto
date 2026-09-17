// swift-tools-version: 6.0
import PackageDescription

// Renders Canto's windows to PNG files offscreen, to review the UI without launching the app
// (launching it would ask for microphone and Accessibility access on behalf of the terminal).
//   swift run -c release CantoSnapshots <output-dir>
let package = Package(
    name: "CantoSnapshots",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/CantoKit"),
        .package(path: "../../Packages/WhisperBridge"),
    ],
    targets: [
        .executableTarget(
            name: "CantoSnapshots",
            dependencies: [
                .product(name: "CantoCore", package: "CantoKit"),
                .product(name: "LocalWhisper", package: "WhisperBridge"),
            ],
            exclude: ["App/CantoApp.swift"],
            swiftSettings: [.define("SNAPSHOTS"), .swiftLanguageMode(.v5)]
        ),
    ]
)
