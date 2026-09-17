import Foundation

/// High-pass filter, peak normalization and a silence gate applied before transcription.
public enum AudioPreprocessor {
    static let highPassHz: Float = 80
    static let targetPeak: Float = 0.9
    static let maxGain: Float = 8
    static let minRMS: Float = 0.004

    public struct Result: Equatable, Sendable {
        public var segment: AudioSegment
        public var skippedAsSilence: Bool
    }

    public static func process(_ segment: AudioSegment, enabled: Bool) -> Result {
        guard enabled, !segment.isEmpty else {
            return Result(segment: segment, skippedAsSilence: false)
        }
        var samples = segment.samples
        highPass(&samples, sampleRate: AudioSegment.sampleRate)
        normalizePeak(&samples)
        if rms(samples) < minRMS {
            return Result(segment: AudioSegment(samples: []), skippedAsSilence: true)
        }
        return Result(segment: AudioSegment(samples: samples), skippedAsSilence: false)
    }

    static func highPass(_ samples: inout [Float], sampleRate: Int) {
        guard let first = samples.first, sampleRate > 0 else { return }
        let rc = 1 / (2 * Float.pi * highPassHz)
        let dt = 1 / Float(sampleRate)
        let alpha = rc / (rc + dt)
        // As if the signal had sat at its first sample forever: a DC input yields 0 from the
        // start instead of a click that decays over the first few milliseconds.
        var previousInput = first
        var previousOutput: Float = 0
        for index in samples.indices {
            let input = samples[index]
            let output = alpha * (previousOutput + input - previousInput)
            previousInput = input
            previousOutput = output
            samples[index] = output
        }
    }

    static func normalizePeak(_ samples: inout [Float]) {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > .ulpOfOne else { return }
        let gain = min(targetPeak / peak, maxGain)
        for index in samples.indices {
            samples[index] = (samples[index] * gain).clamped(to: -1...1)
        }
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }
}
