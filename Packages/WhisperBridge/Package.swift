// swift-tools-version: 6.0
import PackageDescription

// whisper.cpp (built by scripts/build-whisper.sh into a universal static xcframework
// with embedded Metal shaders) behind CantoCore's `Transcriber` protocol.
let package = Package(
    name: "WhisperBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LocalWhisper", targets: ["LocalWhisper"]),
        // Command-line check of the whole recognition path without the app:
        // swift run whisper-smoke <model.bin> <16k-mono.wav> [language] [gpu|cpu]
        .executable(name: "whisper-smoke", targets: ["whisper-smoke"]),
    ],
    dependencies: [
        .package(path: "../CantoKit"),
    ],
    targets: [
        .binaryTarget(name: "whisper", path: "Frameworks/whisper.xcframework"),
        .target(
            name: "LocalWhisper",
            dependencies: ["whisper", .product(name: "CantoCore", package: "CantoKit")],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
        .executableTarget(
            name: "whisper-smoke",
            dependencies: ["LocalWhisper", .product(name: "CantoCore", package: "CantoKit")]
        ),
    ]
)
