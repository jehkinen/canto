import AVFoundation
import CoreAudio
import CantoCore

enum AudioRecorderError: Error {
    case noInputDevice
    case converterUnavailable
}

/// Captures the microphone with AVAudioEngine and delivers 16 kHz mono Float32 chunks.
/// A new engine is built for every session so device switches always take effect and the
/// microphone indicator is only on while Canto is actually listening.
final class AudioRecorder {
    /// Called on the main queue, about 30 times a second.
    var onLevel: ((Float) -> Void)?
    /// Called on the main queue when the input device disappears or changes format mid-session.
    var onInterruption: (() -> Void)?

    let processingQueue = DispatchQueue(label: "canto.audio.processing", qos: .userInitiated)

    /// Only touched on `processingQueue`.
    private var sampleHandler: (([Float]) -> Void)?
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var meter = MicLevelMeter()
    private var lastLevelReport = DispatchTime.now()

    var isRunning: Bool { engine?.isRunning ?? false }

    /// Sets the receiver of converted 16 kHz samples; it is called on `processingQueue`.
    func setSampleHandler(_ handler: (([Float]) -> Void)?) {
        processingQueue.sync { sampleHandler = handler }
    }

    /// Starts capturing from the device with `deviceUID`, or the system default if it is gone.
    /// Returns the name of the device actually used.
    @discardableResult
    func start(deviceUID: String?) throws -> String? {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode

        var device = deviceUID.flatMap(AudioDevices.device(uid:))
        if let chosen = device, let unit = input.audioUnit {
            var id = chosen.id
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                              &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { device = nil }
        }
        if device == nil { device = AudioDevices.defaultInputDevice() }

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
                self.reportLevel(samples)
                self.sampleHandler?(samples)
            }
        }

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.onInterruption?()
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        return device?.name
    }

    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        processingQueue.async {
            self.meter = MicLevelMeter()
            DispatchQueue.main.async { self.onLevel?(0) }
        }
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
