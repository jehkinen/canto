import Foundation
import Testing
@testable import CantoCore

struct AudioPreprocessorTests {
    @Test func normalizesPeakTowardTarget() {
        let result = AudioPreprocessor.process(AudioSegment(samples: [0.1, -0.2, 0.05, -0.15]), enabled: true)
        let peak = result.segment.samples.map(abs).max() ?? 0
        #expect(abs(peak - AudioPreprocessor.targetPeak) < 0.05)
    }

    @Test func skipsNearSilenceSegments() {
        let result = AudioPreprocessor.process(AudioSegment(samples: Array(repeating: 0.0001, count: 800)), enabled: true)
        #expect(result.skippedAsSilence)
        #expect(result.segment.isEmpty)
    }

    @Test func highPassReducesDCOffset() {
        var samples = [Float](repeating: 0.5, count: 256)
        AudioPreprocessor.highPass(&samples, sampleRate: 16_000)
        let mean = samples.reduce(0, +) / Float(samples.count)
        #expect(abs(mean) < 0.05)
    }

    @Test func disabledLeavesAudioUntouched() {
        let segment = AudioSegment(samples: [0.1, 0.2])
        #expect(AudioPreprocessor.process(segment, enabled: false).segment == segment)
    }
}

struct MicLevelMeterTests {
    @Test func silenceStaysLow() {
        var meter = MicLevelMeter()
        meter.update(with: [0, 0, 0.001])
        #expect(meter.level < 0.05)
    }

    @Test func speechLikeSignalRaisesMeter() {
        var meter = MicLevelMeter()
        meter.update(with: [0.2, -0.18, 0.15, -0.12])
        #expect(meter.level > 0.2)
    }
}

struct WAVEncoderTests {
    @Test func writesCanonicalHeader() {
        let data = WAVEncoder.encode(AudioSegment(samples: [0, 0.25, -0.25, 0.5]))
        #expect(data.count == 44 + 8)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        let rate = data[24..<28].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        #expect(rate == 16_000)
    }
}

struct VoiceActivityDetectorTests {
    static let frame = VoiceActivityDetector.frameSamples

    static func sine(_ amplitude: Float) -> [Float] {
        (0..<frame).map { amplitude * sin(2 * .pi * 440 * Float($0) / 16_000) }
    }

    static let silence = [Float](repeating: 0, count: frame)

    static func configuration(minimumSpeechMs: Int = 250, silenceTimeoutMs: Int = 700, maximumSegmentMs: Int = 30_000) -> VADConfiguration {
        VADConfiguration(preSpeechBufferMs: 300, minimumSpeechMs: minimumSpeechMs, silenceTimeoutMs: silenceTimeoutMs, maximumSegmentMs: maximumSegmentMs)
    }

    @Test func silenceDoesNotEmitSegment() {
        let detector = VoiceActivityDetector(configuration: Self.configuration())
        for _ in 0..<20 {
            #expect(detector.push(Self.silence).isEmpty)
        }
    }

    @Test func silenceDoesNotEndWhenDisabled() {
        let detector = VoiceActivityDetector(configuration: Self.configuration(minimumSpeechMs: 100, silenceTimeoutMs: 100))
        detector.endsOnSilence = false
        _ = detector.push(Self.sine(0.8))
        for _ in 0..<20 {
            let ended = detector.push(Self.silence).contains { if case .speechEnded = $0 { true } else { false } }
            #expect(!ended)
        }
    }

    @Test func speechStartAndEndTransitions() {
        let detector = VoiceActivityDetector(configuration: Self.configuration(minimumSpeechMs: 100, silenceTimeoutMs: 100))
        var events: [VoiceActivityDetector.Event] = []
        for _ in 0..<15 { events += detector.push(Self.sine(0.6)) }
        for _ in 0..<20 { events += detector.push(Self.silence) }
        #expect(events.contains(.speechStarted))
        #expect(events.contains { if case .speechEnded = $0 { true } else { false } })
    }

    @Test func longSpeechSplitsAtMaximumSegment() {
        let detector = VoiceActivityDetector(configuration: Self.configuration(minimumSpeechMs: 100, maximumSegmentMs: 500))
        var chunks = 0
        for _ in 0..<40 {
            for case .speechEnded in detector.push(Self.sine(0.6)) { chunks += 1 }
        }
        #expect(chunks >= 1)
    }

    @Test func pushToTalkKeepsAudioEvenWithoutVoice() {
        let detector = VoiceActivityDetector(configuration: Self.configuration(minimumSpeechMs: 100))
        for _ in 0..<10 { _ = detector.push(Self.silence) }
        #expect(detector.flushPushToTalk() != nil)
    }

    @Test func pushToTalkKeepsEverythingFromTheFirstSample() {
        let detector = VoiceActivityDetector(configuration: Self.configuration(maximumSegmentMs: 30_000))
        detector.recordsEverything = true
        // Speech right away, then silence: nothing may be dropped.
        _ = detector.push(Self.sine(0.6))
        for _ in 0..<50 { _ = detector.push(Self.silence) }
        #expect(detector.flushPushToTalk()?.samples.count == Self.frame * 51)
    }

    @Test func pushToTalkSplitsVeryLongRecordings() {
        let detector = VoiceActivityDetector(configuration: Self.configuration(maximumSegmentMs: 500))
        detector.recordsEverything = true
        var chunks = 0
        for _ in 0..<60 {
            for case .speechEnded in detector.push(Self.sine(0.6)) { chunks += 1 }
        }
        #expect(chunks == 2)
        #expect(detector.flushPushToTalk() != nil)
    }

    @Test func pushToTalkDropsRecordingsWithoutVoice() {
        let detector = VoiceActivityDetector(configuration: Self.configuration())
        detector.recordsEverything = true
        for _ in 0..<60 { _ = detector.push(Self.silence) }
        #expect(detector.flushPushToTalk() == nil)
    }

    @Test func pushToTalkSplitsLongRecordingsInAPause() {
        let detector = VoiceActivityDetector(configuration: Self.configuration(maximumSegmentMs: 2_000))
        detector.recordsEverything = true
        var segments: [AudioSegment] = []
        let frames = Array(repeating: Self.sine(0.6), count: 80) + Array(repeating: Self.silence, count: 15)
            + Array(repeating: Self.sine(0.6), count: 30)
        for frame in frames {
            for case .speechEnded(let segment) in detector.push(frame) { segments.append(segment) }
        }
        #expect(segments.count == 1)
        #expect((Self.frame * 80...Self.frame * 95).contains(segments.first?.samples.count ?? 0))
    }

    @Test func ringBufferKeepsNewestSamples() {
        var buffer = RingBuffer(capacity: 3)
        buffer.append([1, 2])
        buffer.append([3, 4, 5])
        #expect(buffer.contents() == [3, 4, 5])
    }
}

struct CompressedAudioEncoderTests {
    @Test func encodesSpeechSizedAudioAsM4A() throws {
        let samples = (0..<16_000 * 3).map { Float(sin(2 * .pi * 220 * Double($0) / 16_000) * 0.4) }
        let data = try #require(CompressedAudioEncoder.m4a(AudioSegment(samples: samples)))
        #expect(String(decoding: data[4..<8], as: UTF8.self) == "ftyp")
        #expect(data.count < WAVEncoder.encode(AudioSegment(samples: samples)).count / 2)
    }
}
