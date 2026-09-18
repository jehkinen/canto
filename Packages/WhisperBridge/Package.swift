// swift-tools-version: 6.2
import PackageDescription

// Local speech engines behind CantoCore's `Transcriber` protocol:
// - LocalWhisper: whisper.cpp, built by scripts/build-whisper.sh into a universal static
//   xcframework with embedded Metal shaders;
// - LocalParakeet: NVIDIA Parakeet TDT v3 through FluidAudio (Core ML on the Neural Engine,
//   Apple silicon only).
let package = Package(
    name: "WhisperBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LocalWhisper", targets: ["LocalWhisper"]),
        .library(name: "LocalParakeet", targets: ["LocalParakeet"]),
        // Command-line check of the whole recognition path without the app:
        // swift run whisper-smoke <model.bin> <16k-mono.wav> [language] [gpu|cpu]
        .executable(name: "whisper-smoke", targets: ["whisper-smoke"]),
    ],
    dependencies: [
        .package(path: "../CantoKit"),
        // No traits: the NeMo text normalizer is a large prebuilt binary Canto does not need,
        // its own text pipeline formats numbers.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.7", traits: []),
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
        .target(
            name: "LocalParakeet",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "CantoCore", package: "CantoKit"),
            ]
        ),
        .executableTarget(
            name: "whisper-smoke",
            dependencies: ["LocalWhisper", .product(name: "CantoCore", package: "CantoKit")]
        ),
    ]
)
