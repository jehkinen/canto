// swift-tools-version: 6.0
import PackageDescription

// Platform-independent Canto logic: settings model, text pipeline, audio DSP,
// OpenAI client, model catalog. Everything here is unit-testable with `swift test`.
let package = Package(
    name: "CantoKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CantoCore", targets: ["CantoCore"]),
        .library(name: "SileroVAD", targets: ["SileroVAD"]),
    ],
    targets: [
        // libfvad: the WebRTC voice activity detector (BSD-3), the fallback when Silero can not load.
        .target(
            name: "CFvad",
            exclude: ["LICENSE"],
            cSettings: [.headerSearchPath("src")]
        ),
        // Skills that ship with Canto (copied into the skills folder the first time it is created) and
        // the language files with the words the text rules need.
        .target(name: "CantoCore", dependencies: ["CFvad"], resources: [.copy("Skills"), .copy("Languages")]),
        // Silero VAD on Core ML, with the model and its MIT license bundled so voice detection works
        // offline from the first launch. CantoCore falls back to libfvad without it.
        .target(name: "SileroVAD", dependencies: ["CantoCore"], resources: [.copy("Model")]),
        .testTarget(name: "CantoCoreTests", dependencies: ["CantoCore"]),
        .testTarget(name: "SileroVADTests", dependencies: ["SileroVAD"]),
    ]
)
