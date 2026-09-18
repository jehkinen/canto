import AudioToolbox
import AVFoundation
import CoreAudio
import CantoCore

enum AudioRecorderError: Error, Equatable {
    case noInputDevice
    case unitUnavailable(OSStatus)
    /// Core Audio did not answer: the start was abandoned so the app stays responsive.
    case timedOut
}

/// Captures the microphone and delivers 16 kHz mono Float32 chunks.
///
/// It records with an input-only HAL unit bound to one device. AVAudioEngine, used before,
/// always drives input and output together: with a chosen microphone it joins it and the
/// speakers into an aggregate device, which AirPods rebuild when they switch to their headset
/// profile. The engine then stopped on every start ("the microphone changed"), and switching
/// to the built-in microphone could hang Core Audio for good.
///
/// Units are started and stopped on a background queue with a timeout, never on the main
/// thread, so a stuck Core Audio call can not freeze the app.
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
    // Only touched on `processingQueue`:
    private var sampleHandler: (([Float]) -> Void)?
    private var meter = MicLevelMeter()
    private var isLive = false
    private var lastLevelReport = DispatchTime.now()
    private var resampler = Resampler()

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
                controller.capture?.stop()
                controller.capture = nil
                let result = Result { try self.makeCapture(deviceUID: deviceUID) }
                if gate.claim() {
                    controller.capture = try? result.get()
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
            controller.capture?.stop()
            controller.capture = nil
            self.processingQueue.async {
                self.meter = MicLevelMeter()
                DispatchQueue.main.async { self.onLevel?(0) }
                completion?()
            }
        }
    }

    /// Runs on a controller's queue.
    private func makeCapture(deviceUID: String?) throws -> Capture {
        processingQueue.sync {
            isLive = false
            resampler = Resampler()
        }
        var candidates: [AudioDeviceID] = []
        if let chosen = deviceUID.flatMap(AudioDevices.device(uid:)) { candidates.append(chosen.id) }
        if let fallback = AudioDevices.defaultInputDevice(), !candidates.contains(fallback.id) { candidates.append(fallback.id) }
        guard !candidates.isEmpty else { throw AudioRecorderError.noInputDevice }

        var lastError: Error = AudioRecorderError.noInputDevice
        for device in candidates {
            do {
                return try Capture(device: device) { [weak self] samples, sampleRate in
                    guard let self else { return }
                    self.processingQueue.async { self.process(samples, sampleRate: sampleRate) }
                } onInterruption: { [weak self] in
                    DispatchQueue.main.async { self?.onInterruption?() }
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Runs on `processingQueue` with mono samples at the device's sample rate.
    private func process(_ samples: [Float], sampleRate: Double) {
        let converted = resampler.convert(samples, from: sampleRate)
        guard !converted.isEmpty else { return }
        if !isLive, converted.contains(where: { abs($0) > 0.001 }) {
            isLive = true
            DispatchQueue.main.async { self.onLive?() }
        }
        reportLevel(converted)
        sampleHandler?(converted)
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

/// An input-only AUHAL unit capturing one device.
private final class Capture {
    private let unit: AudioUnit
    private let device: AudioDeviceID
    private let sampleRate: Double
    private let buffer: AVAudioPCMBuffer
    private let deliver: ([Float], Double) -> Void
    private let interrupted: () -> Void
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var isStopped = false

    /// Starts capturing. `deliver` is called on the audio thread with mono samples and their rate.
    init(device: AudioDeviceID, deliver: @escaping ([Float], Double) -> Void, onInterruption: @escaping () -> Void) throws {
        self.device = device
        self.deliver = deliver
        self.interrupted = onInterruption

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioRecorderError.unitUnavailable(kAudioUnitErr_InvalidElement)
        }
        var instance: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &instance))
        guard let unit = instance else { throw AudioRecorderError.unitUnavailable(kAudioUnitErr_Uninitialized) }
        self.unit = unit

        do {
            // Input on element 1 and no output on element 0: the speakers are left alone.
            var enable: UInt32 = 1
            var disable: UInt32 = 0
            try Self.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                                                &enable, UInt32(MemoryLayout<UInt32>.size)))
            try Self.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                                                &disable, UInt32(MemoryLayout<UInt32>.size)))
            var deviceID = device
            try Self.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                                &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)))

            // The device side of the input element. The unit does not resample, so the app
            // side keeps the device's rate and channels, as non-interleaved Float32.
            var hardware = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1,
                                                &hardware, &size))
            guard hardware.mSampleRate > 0, hardware.mChannelsPerFrame > 0,
                  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hardware.mSampleRate,
                                             channels: hardware.mChannelsPerFrame, interleaved: false) else {
                throw AudioRecorderError.noInputDevice
            }
            var client = format.streamDescription.pointee
            try Self.check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                                &client, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))

            var maximumFrames: UInt32 = 0
            size = UInt32(MemoryLayout<UInt32>.size)
            AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFrames, &size)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(maximumFrames, 8_192)) else {
                throw AudioRecorderError.noInputDevice
            }
            self.sampleRate = hardware.mSampleRate
            self.buffer = buffer
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }

        var callback = AURenderCallbackStruct(inputProc: captureInputProc,
                                              inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        do {
            try Self.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                                &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
            try Self.check(AudioUnitInitialize(unit))
            watchDevice()
            try Self.check(AudioOutputUnitStart(unit))
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        // Once AudioOutputUnitStop returns, no more input callbacks run.
        AudioOutputUnitStop(unit)
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, nil, block)
        }
        listeners.removeAll()
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
    }

    /// Reports the device going away or changing its sample rate: this unit can not continue.
    private func watchDevice() {
        for selector in [kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyNominalSampleRate] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let device = self.device
            let sampleRate = self.sampleRate
            let interrupted = self.interrupted
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                var query = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                       mElement: kAudioObjectPropertyElementMain)
                if selector == kAudioDevicePropertyNominalSampleRate {
                    var rate: Float64 = 0
                    var size = UInt32(MemoryLayout<Float64>.size)
                    guard AudioObjectGetPropertyData(device, &query, 0, nil, &size, &rate) == noErr,
                          rate > 0, rate != sampleRate else { return }
                } else {
                    var alive: UInt32 = 1
                    var size = UInt32(MemoryLayout<UInt32>.size)
                    if AudioObjectGetPropertyData(device, &query, 0, nil, &size, &alive) == noErr, alive != 0 { return }
                }
                interrupted()
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, nil, block) == noErr {
                listeners.append((address, block))
            }
        }
    }

    /// Runs on the real-time audio thread.
    fileprivate func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            timeStamp: UnsafePointer<AudioTimeStamp>, bus: UInt32, frames: UInt32) -> OSStatus {
        guard frames <= buffer.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }
        buffer.frameLength = frames
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for index in buffers.indices {
            buffers[index].mDataByteSize = frames * UInt32(MemoryLayout<Float>.size)
        }
        let status = AudioUnitRender(unit, flags, timeStamp, bus, frames, buffer.mutableAudioBufferList)
        guard status == noErr, let channels = buffer.floatChannelData else { return status }

        let count = Int(frames)
        let channelCount = Int(buffer.format.channelCount)
        var mono = Array(UnsafeBufferPointer(start: channels[0], count: count))
        if channelCount > 1 {
            for channel in 1..<channelCount {
                let samples = channels[channel]
                for index in 0..<count { mono[index] += samples[index] }
            }
            let scale = 1 / Float(channelCount)
            for index in 0..<count { mono[index] *= scale }
        }
        deliver(mono, sampleRate)
        return noErr
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw AudioRecorderError.unitUnavailable(status) }
    }
}

private func captureInputProc(refCon: UnsafeMutableRawPointer,
                              flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                              timeStamp: UnsafePointer<AudioTimeStamp>, bus: UInt32, frames: UInt32,
                              data: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    Unmanaged<Capture>.fromOpaque(refCon).takeUnretainedValue()
        .render(flags: flags, timeStamp: timeStamp, bus: bus, frames: frames)
}

/// Converts mono Float32 at the device rate to 16 kHz, keeping the filter state between chunks.
private struct Resampler {
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioSegment.sampleRate),
                                             channels: 1, interleaved: false)!

    mutating func convert(_ samples: [Float], from sampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        if sampleRate == outputFormat.sampleRate { return samples }
        if inputFormat?.sampleRate != sampleRate {
            inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
            converter = inputFormat.flatMap { AVAudioConverter(from: $0, to: outputFormat) }
        }
        let outputCapacity = AVAudioFrameCount(Double(samples.count) * outputFormat.sampleRate / sampleRate) + 32
        guard let converter, let inputFormat,
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity),
              let destination = input.floatChannelData?[0] else { return [] }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            destination.update(from: source.baseAddress!, count: samples.count)
        }
        var delivered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, output.frameLength > 0, let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

/// A serial queue and the capture it drives, replaced as a whole when a start hangs.
private final class Controller: @unchecked Sendable {
    let queue = DispatchQueue(label: "canto.audio.control", qos: .userInitiated)
    /// Only touched on `queue`.
    var capture: Capture?
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
