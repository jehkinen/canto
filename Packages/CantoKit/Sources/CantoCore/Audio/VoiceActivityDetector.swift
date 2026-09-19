import Foundation

/// Splits a 16 kHz mono stream into phrases: a pre-speech buffer, a silence timeout, a minimum
/// phrase length and a hard maximum length. A `VoiceClassifier` tells which frames hold a voice.
public final class VoiceActivityDetector {
    public enum Event: Equatable, Sendable {
        case speechStarted
        case speechEnded(AudioSegment)
    }

    private enum State { case idle, speaking }

    public var endsOnSilence = true
    /// Push-to-talk: keep every sample from the key press on. The detector would otherwise drop
    /// speech that starts before it has learned the background noise, cutting off the first words.
    public var recordsEverything = false

    /// Samples in each frame the classifier judges.
    public let frameSamples: Int

    private let configuration: VADConfiguration
    private let classifier: any VoiceClassifier
    /// Voiced frames in a row that start a phrase in continuous listening.
    private let onsetFrames: Int
    private var state = State.idle
    private var preBuffer: RingBuffer
    private var segment: [Float] = []
    private var pending: [Float] = []
    private var silenceSamples = 0
    /// Continuous listening: voiced frames in a row heard while idle.
    private var voicedRun = 0
    /// Push-to-talk: whether the classifier heard a voice in each frame of `segment`.
    private var frameVoice: [Bool] = []

    /// Push-to-talk recordings with less voice than this are silence or noise: Whisper would
    /// only invent text for them.
    static let minimumVoiceMs = 100
    /// How far back from the length limit a long push-to-talk recording looks for a pause to split at.
    static let splitSearchMs = 5_000

    public init(configuration: VADConfiguration, classifier: any VoiceClassifier = WebRTCVoiceClassifier()) {
        self.configuration = configuration
        self.classifier = classifier
        frameSamples = classifier.frameSamples
        onsetFrames = max(1, (AudioSegment.sampleCount(milliseconds: classifier.onsetMs) + frameSamples - 1) / frameSamples)
        // The audio kept before speech, plus the frames that confirmed it.
        preBuffer = RingBuffer(capacity: AudioSegment.sampleCount(milliseconds: configuration.preSpeechBufferMs)
            + onsetFrames * frameSamples)
    }

    public func reset() {
        state = .idle
        segment.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        preBuffer.removeAll()
        silenceSamples = 0
        voicedRun = 0
        frameVoice.removeAll()
        classifier.reset()
    }

    /// Feeds 16 kHz mono samples and returns the events they completed.
    public func push(_ samples: [Float]) -> [Event] {
        if recordsEverything {
            return pushEverything(samples)
        }
        pending.append(contentsOf: samples)
        var events: [Event] = []
        var offset = 0
        while pending.count - offset >= frameSamples {
            let frame = Array(pending[offset..<offset + frameSamples])
            offset += frameSamples
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
        if recordsEverything {
            segment.append(contentsOf: pending)
            pending.removeAll(keepingCapacity: true)
            let voiced = hasVoice(frameVoice[...])
            frameVoice.removeAll()
            guard voiced, !segment.isEmpty else {
                segment.removeAll(keepingCapacity: true)
                return nil
            }
            return takeSegment()
        }
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

    /// Push-to-talk: keeps every sample, and still runs the VAD to know where the voice is.
    private func pushEverything(_ samples: [Float]) -> [Event] {
        pending.append(contentsOf: samples)
        var offset = 0
        while pending.count - offset >= frameSamples {
            let frame = Array(pending[offset..<offset + frameSamples])
            offset += frameSamples
            segment.append(contentsOf: frame)
            frameVoice.append(classifier.isVoice(frame))
        }
        pending.removeFirst(offset)

        var events: [Event] = []
        let limitFrames = max(1, AudioSegment.sampleCount(milliseconds: configuration.maximumSegmentMs) / frameSamples)
        while frameVoice.count >= limitFrames {
            let split = splitFrame(limit: limitFrames)
            let voiced = hasVoice(frameVoice[..<split])
            let samples = Array(segment.prefix(split * frameSamples))
            segment.removeFirst(split * frameSamples)
            frameVoice.removeFirst(split)
            if voiced { events.append(.speechEnded(AudioSegment(samples: samples))) }
        }
        return events
    }

    /// Where to cut a recording that reached the length limit: the middle of the longest pause
    /// in its last few seconds, so a word is not cut in two. Without a pause, at the limit.
    private func splitFrame(limit: Int) -> Int {
        let searchStart = max(1, limit - AudioSegment.sampleCount(milliseconds: Self.splitSearchMs) / frameSamples)
        var best = (start: limit, length: 0)
        var runStart: Int?
        for index in searchStart...limit {
            let isPause = index < limit && !frameVoice[index]
            if isPause {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                if index - start > best.length { best = (start, index - start) }
                runStart = nil
            }
        }
        return best.length > 0 ? best.start + best.length / 2 : limit
    }

    private func hasVoice(_ frames: ArraySlice<Bool>) -> Bool {
        frames.lazy.filter { $0 }.count * frameSamples >= AudioSegment.sampleCount(milliseconds: Self.minimumVoiceMs)
    }

    private func drainPendingFrames() {
        var offset = 0
        while pending.count - offset >= frameSamples {
            _ = process(Array(pending[offset..<offset + frameSamples]))
            offset += frameSamples
        }
        pending.removeFirst(offset)
    }

    private func process(_ frame: [Float]) -> Event? {
        let voice = classifier.isVoice(frame)

        switch state {
        case .idle:
            preBuffer.append(frame)
            guard voice else {
                voicedRun = 0
                return nil
            }
            // A single voiced frame is often a click or a breath: speech has to last `onsetFrames`.
            voicedRun += 1
            guard voicedRun >= onsetFrames else { return nil }
            voicedRun = 0
            state = .speaking
            silenceSamples = 0
            segment = preBuffer.contents()
            return .speechStarted
        case .speaking:
            segment.append(contentsOf: frame)
            if voice {
                silenceSamples = 0
            } else {
                silenceSamples += frameSamples
                if endsOnSilence,
                   silenceSamples >= AudioSegment.sampleCount(milliseconds: configuration.silenceTimeoutMs) {
                    if segment.count >= AudioSegment.sampleCount(milliseconds: configuration.minimumSpeechMs) {
                        state = .idle
                        return .speechEnded(takeSegment())
                    }
                    // Too short to be a phrase: drop it, but keep the classifier's state.
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
