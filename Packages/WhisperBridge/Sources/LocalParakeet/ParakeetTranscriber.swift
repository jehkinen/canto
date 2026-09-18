import CantoCore
import FluidAudio
import Foundation

/// Local speech recognition with NVIDIA Parakeet TDT 0.6B v3 (25 European languages, Russian
/// included) running as Core ML on the Neural Engine. The model is loaded lazily and kept.
///
/// Parakeet detects the language itself and takes no text prompt: vocabulary terms only fix
/// the spelling afterwards. The language hint is not passed either: for Russian it filters out
/// Latin tokens, which would break English terms in Russian speech.
public final class ParakeetTranscriber: Transcriber, @unchecked Sendable {
    public let directory: URL
    private let engine: Engine

    /// `directory` is the model folder a `ParakeetModels.download(to:)` call filled.
    public init(directory: URL) {
        self.directory = directory
        engine = Engine(directory: directory)
    }

    /// Loads the model ahead of the first dictation. The first load on a Mac also compiles the
    /// model for the Neural Engine, which takes several seconds.
    public func prepare() async throws {
        _ = try await engine.manager()
    }

    public func transcribe(_ segment: AudioSegment, language: String?, prompt: String?) async throws -> String {
        try await engine.transcribe(segment.samples)
    }
}

private actor Engine {
    let directory: URL
    private var loaded: AsrManager?

    init(directory: URL) {
        self.directory = directory
    }

    func manager() async throws -> AsrManager {
        if let loaded { return loaded }
        guard ParakeetModels.isInstalled(at: directory) else {
            throw TranscriptionError.modelNotFound(directory.path)
        }
        do {
            let models = try await AsrModels.load(from: directory, version: .v3)
            let manager = AsrManager()
            try await manager.loadModels(models)
            loaded = manager
            return manager
        } catch {
            throw TranscriptionError.modelLoadFailed("Parakeet v3: \(error.localizedDescription)")
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let manager = try await manager()
        // Parakeet refuses audio shorter than a second; silence after a short phrase is harmless.
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: AudioSegment.sampleRate) + 1_600
        let padded = samples.count >= minimum ? samples : samples + [Float](repeating: 0, count: minimum - samples.count)
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        do {
            let result = try await manager.transcribe(padded, decoderState: &state, language: nil)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranscriptionError.inferenceFailed("Parakeet v3: \(error.localizedDescription)")
        }
    }
}

/// Downloads and checks the Parakeet v3 Core ML bundle.
public enum ParakeetModels {
    /// Parakeet runs on the Neural Engine of Apple silicon; Intel Macs keep Whisper.
    public static var isSupported: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    public static func isInstalled(at directory: URL) -> Bool {
        AsrModels.modelsExist(at: directory, version: .v3)
    }

    /// Downloads the model files into `directory`, reporting the completed fraction (0…1).
    public static func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await AsrModels.download(to: directory, version: .v3) { update in
            progress(update.fractionCompleted)
        }
        guard isInstalled(at: directory) else {
            throw TranscriptionError.modelNotFound(directory.path)
        }
    }
}
