import AVFoundation
import CantoCore
import Foundation
import Testing
@testable import SileroVAD

struct SileroVoiceClassifierTests {
    static let window = SileroVoiceClassifier.windowSamples

    /// White noise from a fixed seed, so the result does not depend on luck.
    static func noise(seconds: Double, amplitude: Float) -> [Float] {
        var state: UInt32 = 12_345
        return (0..<Int(seconds * 16_000)).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return (Float(state) / Float(UInt32.max) * 2 - 1) * amplitude
        }
    }

    static func tone(seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { 0.6 * sin(2 * Float.pi * 440 * Float($0) / 16_000) }
    }

    /// A sentence read by the system voice, as 16 kHz mono.
    static func speech() throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("silero-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000",
                         "Please send the weekly report before the meeting on Friday afternoon."]
        try say.run()
        say.waitUntilExit()
        try #require(say.terminationStatus == 0)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    static func windows(_ samples: [Float]) -> [[Float]] {
        stride(from: 0, through: samples.count - window, by: window).map { Array(samples[$0..<$0 + window]) }
    }

    static func voicedFraction(_ samples: [Float], classifier: SileroVoiceClassifier) -> Double {
        let windows = windows(samples)
        return Double(windows.filter(classifier.isVoice).count) / Double(windows.count)
    }

    @Test func silenceNoiseAndTonesAreNotVoice() throws {
        let classifier = try SileroVoiceClassifier()
        #expect(Self.voicedFraction([Float](repeating: 0, count: 16_000), classifier: classifier) == 0)
        #expect(Self.voicedFraction(Self.noise(seconds: 2, amplitude: 0.05), classifier: classifier) == 0)
        #expect(Self.voicedFraction(Self.tone(seconds: 2), classifier: classifier) == 0)
    }

    @Test func speechIsVoice() throws {
        let classifier = try SileroVoiceClassifier()
        #expect(Self.voicedFraction(try Self.speech(), classifier: classifier) > 0.6)
    }

    @Test func resetStartsOverLikeANewClassifier() throws {
        let speech = Self.windows(try Self.speech())
        let used = try SileroVoiceClassifier()
        for window in speech { _ = used.isVoice(window) }
        used.reset()
        let fresh = try SileroVoiceClassifier()
        for window in speech.prefix(40) {
            #expect(abs(try used.probability(of: window) - fresh.probability(of: window)) < 0.001)
        }
    }

    @Test func failureHandsTheRecordingToLibfvad() throws {
        let classifier = try SileroVoiceClassifier()
        let tone = Self.windows(Self.tone(seconds: 1))
        #expect(!tone.contains(where: classifier.isVoice))
        // A window of the wrong size makes the model fail; libfvad, unlike Silero, takes a tone for a voice.
        #expect(!classifier.isVoice([0, 0, 0]))
        #expect(tone.contains(where: classifier.isVoice))
    }

    @Test func makeGivesAClassifierOnceTheModelIsLoaded() async throws {
        SileroVoiceClassifier.prepare()
        var attempts = 0
        while SileroVoiceClassifier.make() == nil, attempts < 100 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(SileroVoiceClassifier.make() != nil)
    }

    @Test func continuousListeningCutsOnePhraseOutOfNoise() throws {
        let configuration = VADConfiguration(preSpeechBufferMs: 300, minimumSpeechMs: 250, silenceTimeoutMs: 700, maximumSegmentMs: 30_000)
        let detector = VoiceActivityDetector(configuration: configuration, classifier: try SileroVoiceClassifier())
        let speech = try Self.speech()
        let stream = Self.noise(seconds: 2, amplitude: 0.02) + speech + Self.noise(seconds: 2, amplitude: 0.02)
        var phrases: [AudioSegment] = []
        // The recorder delivers about 10 ms at a time.
        for start in stride(from: 0, to: stream.count, by: 160) {
            for case .speechEnded(let phrase) in detector.push(Array(stream[start..<min(start + 160, stream.count)])) {
                phrases.append(phrase)
            }
        }
        let speechSeconds = AudioSegment(samples: speech).duration
        #expect(phrases.count == 1)
        // The speech with the audio kept before it and the pause after it, not the noise around it.
        #expect((speechSeconds - 0.3...speechSeconds + 1.3).contains(phrases.first?.duration ?? 0))
    }
}
