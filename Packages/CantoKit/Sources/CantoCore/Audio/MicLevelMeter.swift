import Foundation

/// A 0…1 input meter with fast attack and slow release, tuned for speech.
public struct MicLevelMeter: Sendable {
    public private(set) var level: Float = 0

    public init() {}

    public mutating func update(with samples: UnsafeBufferPointer<Float>) {
        guard !samples.isEmpty else { return }
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        // Typical speech peaks land around 0.05–0.35.
        let instant = (peak * 4.5).clamped(to: 0...1)
        level = max(instant, level * 0.7)
    }

    public mutating func update(with samples: [Float]) {
        samples.withUnsafeBufferPointer { update(with: $0) }
    }

    public mutating func decay() {
        level = level < 0.001 ? 0 : level * 0.86
    }
}
