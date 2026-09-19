import CFvad
import Foundation

/// Tells a voice from silence and noise in fixed-size frames of 16 kHz mono audio.
/// The detector passes every frame in order, so a classifier may carry state from one to the next.
public protocol VoiceClassifier: AnyObject {
    /// Samples in each frame passed to `isVoice`.
    var frameSamples: Int { get }
    /// How long a voice has to last before continuous listening takes it for the start of a phrase;
    /// 0 starts on the first voiced frame.
    var onsetMs: Int { get }
    func isVoice(_ frame: [Float]) -> Bool
    /// Forgets the audio heard so far.
    func reset()
}

/// The WebRTC detector (libfvad) in its least aggressive mode. It needs no model, which makes it
/// the fallback for Silero, but it takes tones, hum and steady noise for a voice too.
public final class WebRTCVoiceClassifier: VoiceClassifier {
    public static let defaultFrameSamples = AudioSegment.sampleCount(milliseconds: 20)

    public let frameSamples: Int
    public let onsetMs = 0
    private let vad: OpaquePointer
    /// libfvad takes 10, 20 or 30 ms: a frame of another length is judged by its longest such prefix.
    private let judgedSamples: Int

    public init(frameSamples: Int = WebRTCVoiceClassifier.defaultFrameSamples) {
        self.frameSamples = frameSamples
        judgedSamples = [30, 20, 10]
            .map { AudioSegment.sampleCount(milliseconds: $0) }
            .first { $0 <= frameSamples } ?? AudioSegment.sampleCount(milliseconds: 10)
        vad = fvad_new()
        configure()
    }

    deinit {
        fvad_free(vad)
    }

    public func isVoice(_ frame: [Float]) -> Bool {
        guard frame.count >= judgedSamples else { return false }
        let pcm = frame.prefix(judgedSamples).map { Int16($0.clamped(to: -1...1) * Float(Int16.max)) }
        return pcm.withUnsafeBufferPointer { fvad_process(vad, $0.baseAddress, $0.count) } == 1
    }

    public func reset() {
        fvad_reset(vad)
        configure()
    }

    private func configure() {
        fvad_set_mode(vad, 0)  // "quality", the least aggressive mode
        fvad_set_sample_rate(vad, Int32(AudioSegment.sampleRate))
    }
}
