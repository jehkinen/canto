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
    ],
    targets: [
        // libfvad: the WebRTC voice activity detector the original app used (BSD-3).
        .target(
            name: "CFvad",
            exclude: ["LICENSE"],
            cSettings: [.headerSearchPath("src")]
        ),
        // Skills that ship with Canto: copied into the skills folder the first time it is created.
        .target(name: "CantoCore", dependencies: ["CFvad"], resources: [.copy("Skills")]),
        .testTarget(name: "CantoCoreTests", dependencies: ["CantoCore"]),
    ]
)
