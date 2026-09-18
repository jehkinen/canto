import AVFoundation
import CoreAudio
import CantoCore

enum AudioRecorderError: Error {
    case noInputDevice
    case converterUnavailable
    /// Core Audio did not answer: the start was abandoned so the app stays responsive.
    case timedOut
}

/// Captures the microphone with AVAudioEngine and delivers 16 kHz mono Float32 chunks.
/// A new engine is built for every session so device switches always take effect and the
/// microphone indicator is only on while Canto is actually listening.
///
/// The engine is driven from a background queue, never the main thread: when devices change,
/// AVAudioEngine can wait on Core Audio for good (seen after switching from AirPods to the
/// built-in microphone), and on the main thread that froze the whole app.
final class AudioRecorder {
    /// Called on the main queue, about 30 times a second.
    var onLevel: ((Float) -> Void)?
    /// Called on the main queue when the input device disappears or changes format mid-session.
    var onInterruption: (() -> Void)?
    /// Called on the main queue once per session, when the first real signal arrives. Bluetooth
    /// headsets deliver silence for up to a second while they switch to their microphone.
    var onLive: (() -> Void)?

    let processingQueue = DispatchQueue(label: "canto.audio.processing", qos: .userInitiated)

    /// Only touched on the main thread. Replaced when a start hangs inside Core Audio.
    private var controller = Controller()
    /// Only touched on `processingQueue`.
    private var sampleHandler: (([Float]) -> Void)?
    private var meter = MicLevelMeter()
    /// Only touched on `processingQueue`.
    private var isLive = false
    private var lastLevelReport = DispatchTime.now()

    /// Sets the receiver of converted 16 kHz samples; it is called on `processingQueue`.
    func setSampleHandler(_ handler: (([Float]) -> Void)?) {
        processingQueue.sync { sampleHandler = handler }
    }

    /// Starts capturing from the device with `deviceUID`, or the system default if it is gone.
    /// Throws `timedOut` when Core Audio does not answer in time.
    @MainActor
    func start(deviceUID: String?, timeout: TimeInterval = 5) async throws {
        let controller = self.controller
        let gate = ResumeGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controller.queue.async {
                controller.session?.stop()
                controller.session = nil
                let result = Result { try self.makeSession(deviceUID: deviceUID) }
                if gate.claim() {
                    controller.session = try? result.get()
                    continuation.resume(with: result.map { _ in () })
                } else {
                    // The caller gave up on this start; do not leave the microphone on.
                    try? result.get().stop()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard gate.claim() else { return }
                // The queue is stuck inside Core Audio. Later sessions get a fresh one, and
                // whatever the stuck queue does once it wakes up cannot touch them.
                if self.controller === controller { self.controller = Controller() }
                continuation.resume(throwing: AudioRecorderError.timedOut)
            }
        }
    }

    /// Stops capturing. `completion` runs on `processingQueue` after the last captured chunk.
    @MainActor
    func stop(completion: (() -> Void)? = nil) {
        let controller = self.controller
        controller.queue.async {
            controller.session?.stop()
            controller.session = nil
            self.processingQueue.async {
                self.meter = MicLevelMeter()
                DispatchQueue.main.async { self.onLevel?(0) }
                completion?()
            }
        }
    }

    /// Runs on a controller's queue.
    private func makeSession(deviceUID: String?) throws -> Session {
        processingQueue.sync { isLive = false }
        let engine = AVAudioEngine()
        let input = engine.inputNode

        if let chosen = deviceUID.flatMap(AudioDevices.device(uid:)), let unit = input.audioUnit {
            var id = chosen.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        let hardwareFormat = input.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioSegment.sampleRate),
                                               channels: 1, interleaved: false) else {
            throw AudioRecorderError.converterUnavailable
        }

        // The converter follows the format the tap actually delivers, which can differ from
        // what the node reported when a device switches profiles (Bluetooth headsets do).
        var converter: AVAudioConverter?
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            if converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: targetFormat)
                converter?.downmix = true
            }
            guard let converter else { return }
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var delivered = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if delivered {
                    status.pointee = .noDataNow
                    return nil
                }
                delivered = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, output.frameLength > 0, let channel = output.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            self.processingQueue.async {
                if !self.isLive, samples.contains(where: { abs($0) > 0.001 }) {
                    self.isLive = true
                    DispatchQueue.main.async { self.onLive?() }
                }
                self.reportLevel(samples)
                self.sampleHandler?(samples)
            }
        }

        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.onInterruption?()
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            NotificationCenter.default.removeObserver(observer)
            input.removeTap(onBus: 0)
            throw error
        }
        return Session(engine: engine, observer: observer)
    }

    private func reportLevel(_ samples: [Float]) {
        meter.update(with: samples)
        let now = DispatchTime.now()
        guard now.uptimeNanoseconds - lastLevelReport.uptimeNanoseconds > 33_000_000 else { return }
        lastLevelReport = now
        let level = meter.level
        meter.decay()
        DispatchQueue.main.async { self.onLevel?(level) }
    }
}

/// A running capture engine.
private struct Session {
    let engine: AVAudioEngine
    let observer: NSObjectProtocol

    func stop() {
        NotificationCenter.default.removeObserver(observer)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

/// A serial queue and the engine it drives, replaced as a whole when a start hangs.
private final class Controller: @unchecked Sendable {
    let queue = DispatchQueue(label: "canto.audio.control", qos: .userInitiated)
    /// Only touched on `queue`.
    var session: Session?
}

/// Lets exactly one of two racing callbacks (the start or its timeout) resume a continuation.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
