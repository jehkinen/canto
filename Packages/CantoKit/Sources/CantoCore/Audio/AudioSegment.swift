import Foundation

/// Mono 16 kHz audio as Whisper expects it.
public struct AudioSegment: Equatable, Sendable {
    public static let sampleRate = 16_000

    public var samples: [Float]

    public init(samples: [Float]) {
        self.samples = samples
    }

    public var isEmpty: Bool { samples.isEmpty }
    public var duration: TimeInterval { Double(samples.count) / Double(Self.sampleRate) }

    static func sampleCount(milliseconds: Int) -> Int {
        milliseconds * sampleRate / 1000
    }
}
