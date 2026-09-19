import CantoCore
@preconcurrency import CoreML
import Foundation
import OSLog

private let logger = Logger(subsystem: "io.github.jehkinen.canto", category: "vad")

/// Silero VAD v6 (MIT, github.com/snakers4/silero-vad) on Core ML: the probability of speech in
/// each 32 ms window. It ignores the tones, hum and steady noise the WebRTC detector takes for a
/// voice and Whisper turns into invented text: arXiv 2501.11378 measured 0.2% hallucinations left
/// after Silero against 12–15% after WebRTC.
///
/// The model ships with the app, so it works offline from the first launch: FluidInference's
/// conversion `silero-vad-unified-v6.0.0.mlmodelc` from huggingface.co/FluidInference/silero-vad-coreml
/// (revision b419383), 0.9 MB. FluidAudio's `VadManager` is not used: it is an actor, one async
/// call per chunk, and runs only the 256 ms variant, whose noisy-OR probability is too coarse for
/// pauses and passes noise at this threshold.
public final class SileroVoiceClassifier: VoiceClassifier {
    /// Silero's window at 16 kHz.
    public static let windowSamples = 512
    /// The model also sees this much of the previous window.
    static let contextSamples = 64
    static let stateSize = 128
    /// Handy's threshold, below Silero's 0.5 so quiet word endings stay in the phrase. Silence,
    /// noise and tones stay under 0.2, speech is mostly above 0.8.
    public static let threshold: Float = 0.3

    public let frameSamples = SileroVoiceClassifier.windowSamples
    /// Two windows, as in Handy: a single loud window is more often a click than a word.
    public let onsetMs = 60

    private let model: SileroModel
    /// The previous window's last `contextSamples`, then the current window.
    private let audio: MLMultiArray
    private var hiddenState: MLMultiArray
    private var cellState: MLMultiArray
    /// Takes over for the rest of the recording if the model fails in the middle of it.
    private var fallback: WebRTCVoiceClassifier?

    /// Loads the bundled model and blocks until it is ready; the app uses `make()` instead.
    public convenience init() throws {
        try self.init(model: SileroModel())
    }

    init(model: SileroModel) throws {
        self.model = model
        audio = try MLMultiArray(shape: [1, NSNumber(value: Self.contextSamples + Self.windowSamples)], dataType: .float32)
        hiddenState = try Self.zeroState()
        cellState = try Self.zeroState()
        clearContext()
    }

    public func isVoice(_ frame: [Float]) -> Bool {
        if let fallback { return fallback.isVoice(frame) }
        do {
            return try probability(of: frame) >= Self.threshold
        } catch {
            logger.error("Silero VAD failed, libfvad takes over: \(error.localizedDescription, privacy: .public)")
            let fallback = WebRTCVoiceClassifier(frameSamples: frameSamples)
            self.fallback = fallback
            return fallback.isVoice(frame)
        }
    }

    public func reset() {
        clearContext()
        if let hidden = try? Self.zeroState(), let cell = try? Self.zeroState() {
            hiddenState = hidden
            cellState = cell
        }
        fallback?.reset()
    }

    /// The probability of speech in one window. The model's memory carries over to the next one.
    func probability(of frame: [Float]) throws -> Float {
        guard frame.count == Self.windowSamples else { throw SileroError.wrongWindow(frame.count) }
        audio.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            frame.withUnsafeBufferPointer { window in
                buffer.baseAddress!.advanced(by: Self.contextSamples)
                    .update(from: window.baseAddress!, count: Self.windowSamples)
            }
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "audio_input": audio,
            "hidden_state": hiddenState,
            "cell_state": cellState,
        ])
        let output = try model.prediction(from: input)
        guard let probability = output.featureValue(for: "vad_output")?.multiArrayValue,
              let hidden = output.featureValue(for: "new_hidden_state")?.multiArrayValue,
              let cell = output.featureValue(for: "new_cell_state")?.multiArrayValue else {
            throw SileroError.unexpectedOutput
        }
        hiddenState = hidden
        cellState = cell
        audio.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            buffer.baseAddress!.update(from: buffer.baseAddress!.advanced(by: Self.windowSamples), count: Self.contextSamples)
        }
        return probability[0].floatValue
    }

    private func clearContext() {
        audio.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            buffer.update(repeating: 0)
        }
    }

    private static func zeroState() throws -> MLMultiArray {
        let state = try MLMultiArray(shape: [1, NSNumber(value: stateSize)], dataType: .float32)
        state.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in buffer.update(repeating: 0) }
        return state
    }
}

extension SileroVoiceClassifier {
    /// Starts loading the model in the background, once. Called at launch, so the first recording
    /// already has it; loading takes about a tenth of a second.
    public static func prepare() {
        _ = ModelLoader.shared.model()
    }

    /// A classifier for a new recording, or nil while the model is still loading or if it could
    /// not be loaded: the caller then uses libfvad and the recording does not wait.
    public static func make() -> SileroVoiceClassifier? {
        guard let model = ModelLoader.shared.model() else { return nil }
        return try? SileroVoiceClassifier(model: model)
    }
}

enum SileroError: Error {
    case modelMissing
    case wrongWindow(Int)
    case unexpectedOutput
}

/// The bundled Core ML model, shared by every recording.
final class SileroModel: @unchecked Sendable {
    static let resourceName = "silero-vad-unified-v6.0.0"

    private let model: MLModel
    /// Core ML does not promise that one model predicts on several threads at once. In the app
    /// every call comes from the recorder's queue, so the lock is never contended there.
    private let lock = NSLock()

    init() throws {
        guard let url = Bundle.module.url(forResource: Self.resourceName, withExtension: "mlmodelc", subdirectory: "Model") else {
            throw SileroError.modelMissing
        }
        let configuration = MLModelConfiguration()
        // A window takes about 0.3 ms on the CPU. The Neural Engine would add a compile step to
        // the first load and compete with Parakeet, and Intel Macs do not have one.
        configuration.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: url, configuration: configuration)
    }

    func prediction(from input: MLFeatureProvider) throws -> MLFeatureProvider {
        lock.lock()
        defer { lock.unlock() }
        return try model.prediction(from: input)
    }
}

/// Loads the model once, off the main thread.
private final class ModelLoader: @unchecked Sendable {
    static let shared = ModelLoader()

    private enum State {
        case idle, loading, ready(SileroModel), failed
    }

    private let lock = NSLock()
    private var state = State.idle

    /// The loaded model; starts loading it if nobody has asked yet.
    func model() -> SileroModel? {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .ready(let model):
            return model
        case .idle:
            state = .loading
            DispatchQueue.global(qos: .userInitiated).async { self.load() }
            return nil
        case .loading, .failed:
            return nil
        }
    }

    private func load() {
        let start = Date()
        let result = Result { try SileroModel() }
        lock.lock()
        defer { lock.unlock() }
        switch result {
        case .success(let model):
            state = .ready(model)
            logger.info("Silero VAD ready in \(Date().timeIntervalSince(start), format: .fixed(precision: 2), privacy: .public)s")
        case .failure(let error):
            state = .failed
            logger.error("Silero VAD could not load, libfvad is used: \(String(describing: error), privacy: .public)")
        }
    }
}
