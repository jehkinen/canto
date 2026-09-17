import CFvad
import Foundation

/// Splits a 16 kHz mono stream into phrases with the WebRTC voice activity detector (libfvad):
/// a pre-speech buffer, a silence timeout, a minimum phrase length and a hard maximum length.
public final class VoiceActivityDetector {
    public enum Event: Equatable, Sendable {
        case speechStarted
        case speechEnded(AudioSegment)
    }

    static let frameMs = 20
    static let frameSamples = AudioSegment.sampleCount(milliseconds: frameMs)

    private enum State { case idle, speaking }

    public var endsOnSilence = true

    private let configuration: VADConfiguration
    private let vad: OpaquePointer
    private var state = State.idle
    private var preBuffer: RingBuffer
    private var segment: [Float] = []
    private var pending: [Float] = []
    private var silenceSamples = 0

    public init(configuration: VADConfiguration) {
        self.configuration = configuration
        vad = fvad_new()
        fvad_set_mode(vad, 0)  // "quality", the least aggressive mode
        fvad_set_sample_rate(vad, Int32(AudioSegment.sampleRate))
        preBuffer = RingBuffer(capacity: max(
            AudioSegment.sampleCount(milliseconds: configuration.preSpeechBufferMs),
            Self.frameSamples
        ))
    }

    deinit {
        fvad_free(vad)
    }

    public func reset() {
        state = .idle
        segment.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        preBuffer.removeAll()
        silenceSamples = 0
        fvad_reset(vad)
        fvad_set_mode(vad, 0)
        fvad_set_sample_rate(vad, Int32(AudioSegment.sampleRate))
    }

    /// Feeds 16 kHz mono samples and returns the events they completed.
    public func push(_ samples: [Float]) -> [Event] {
        pending.append(contentsOf: samples)
        var events: [Event] = []
        var offset = 0
        while pending.count - offset >= Self.frameSamples {
            let frame = Array(pending[offset..<offset + Self.frameSamples])
            offset += Self.frameSamples
            if let event = process(frame) {
                events.append(event)
            }
        }
        pending.removeFirst(offset)
        return events
    }

    /// Ends continuous listening: returns the phrase in progress, if any.
    public func flush() -> AudioSegment? {
        drainPendingFrames()
        guard state == .speaking, !segment.isEmpty else { return nil }
        state = .idle
        return takeSegment()
    }

    /// Ends push-to-talk: everything that was recorded counts, even if the VAD never fired.
    public func flushPushToTalk() -> AudioSegment? {
        drainPendingFrames()
        if !segment.isEmpty {
            state = .idle
            return takeSegment()
        }
        let buffered = preBuffer.contents()
        if buffered.count >= AudioSegment.sampleCount(milliseconds: configuration.minimumSpeechMs) {
            reset()
            return AudioSegment(samples: buffered)
        }
        return nil
    }

    private func drainPendingFrames() {
        var offset = 0
        while pending.count - offset >= Self.frameSamples {
            _ = process(Array(pending[offset..<offset + Self.frameSamples]))
            offset += Self.frameSamples
        }
        pending.removeFirst(offset)
    }

    private func process(_ frame: [Float]) -> Event? {
        let pcm = frame.map { Int16($0.clamped(to: -1...1) * Float(Int16.max)) }
        let isVoice = pcm.withUnsafeBufferPointer { fvad_process(vad, $0.baseAddress, $0.count) } == 1

        switch state {
        case .idle:
            preBuffer.append(frame)
            if isVoice {
                state = .speaking
                silenceSamples = 0
                segment = preBuffer.contents()
                return .speechStarted
            }
        case .speaking:
            segment.append(contentsOf: frame)
            if isVoice {
                silenceSamples = 0
            } else {
                silenceSamples += Self.frameSamples
                if endsOnSilence,
                   silenceSamples >= AudioSegment.sampleCount(milliseconds: configuration.silenceTimeoutMs) {
                    if segment.count >= AudioSegment.sampleCount(milliseconds: configuration.minimumSpeechMs) {
                        state = .idle
                        return .speechEnded(takeSegment())
                    }
                    // Too short to be a phrase: drop it but keep the VAD's noise model.
                    state = .idle
                    segment.removeAll(keepingCapacity: true)
                    preBuffer.removeAll()
                    silenceSamples = 0
                    return nil
                }
            }
            if segment.count >= AudioSegment.sampleCount(milliseconds: configuration.maximumSegmentMs) {
                state = .idle
                return .speechEnded(takeSegment())
            }
        }
        return nil
    }

    private func takeSegment() -> AudioSegment {
        let samples = segment
        segment = []
        silenceSamples = 0
        preBuffer.removeAll()
        return AudioSegment(samples: samples)
    }
}

/// Fixed-capacity FIFO that keeps the most recent samples.
struct RingBuffer {
    private var storage: [Float]
    private var start = 0
    private(set) var count = 0

    init(capacity: Int) {
        storage = [Float](repeating: 0, count: max(capacity, 1))
    }

    mutating func append(_ samples: [Float]) {
        let capacity = storage.count
        for sample in samples.suffix(capacity) {
            storage[(start + count) % capacity] = sample
            if count < capacity {
                count += 1
            } else {
                start = (start + 1) % capacity
            }
        }
    }

    func contents() -> [Float] {
        (0..<count).map { storage[(start + $0) % storage.count] }
    }

    mutating func removeAll() {
        start = 0
        count = 0
    }
}
