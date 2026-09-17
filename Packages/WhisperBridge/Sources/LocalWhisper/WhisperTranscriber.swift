import Foundation
import CantoCore
import whisper

/// Local speech recognition with whisper.cpp. The model is loaded lazily and kept in memory;
/// inference runs on a dedicated serial queue because a whisper context is not thread-safe
/// and a transcription can take seconds (too long to block Swift's cooperative pool).
public final class WhisperTranscriber: Transcriber, @unchecked Sendable {
    public struct Configuration: Equatable, Sendable {
        public var modelURL: URL
        public var useGPU: Bool
        public var beamSize: Int

        public init(modelURL: URL, useGPU: Bool, beamSize: Int) {
            self.modelURL = modelURL
            self.useGPU = useGPU
            self.beamSize = beamSize
        }
    }

    public let configuration: Configuration
    private let queue = DispatchQueue(label: "canto.whisper", qos: .userInitiated)
    private var context: OpaquePointer?

    public init(configuration: Configuration) {
        self.configuration = configuration
        Self.silenceLogging()
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    /// Loads the model ahead of the first dictation so it starts without a delay.
    public func prepare() async throws {
        try await run { _ = try self.loadIfNeeded() }
    }

    public func transcribe(_ segment: AudioSegment, language: String?, prompt: String?) async throws -> String {
        try await run {
            let context = try self.loadIfNeeded()
            return try self.infer(context: context, samples: segment.samples, language: language, prompt: prompt)
        }
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private func loadIfNeeded() throws -> OpaquePointer {
        if let context { return context }
        let path = configuration.modelURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw TranscriptionError.modelNotFound(path)
        }
        var parameters = whisper_context_default_params()
        parameters.use_gpu = configuration.useGPU
        guard let loaded = whisper_init_from_file_with_params(path, parameters) else {
            throw TranscriptionError.modelLoadFailed(configuration.modelURL.lastPathComponent)
        }
        context = loaded
        return loaded
    }

    private func infer(context: OpaquePointer, samples: [Float], language: String?, prompt: String?) throws -> String {
        let beamSize = Int32(configuration.beamSize)
        var parameters = whisper_full_default_params(beamSize > 1 ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY)
        parameters.greedy.best_of = 1
        parameters.beam_search.beam_size = max(beamSize, 1)
        parameters.beam_search.patience = -1
        parameters.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        parameters.print_special = false
        parameters.print_progress = false
        parameters.print_realtime = false
        parameters.print_timestamps = false
        parameters.entropy_thold = 2.2
        parameters.logprob_thold = -0.8
        parameters.no_speech_thold = 0.55
        // Short phrases otherwise come back as sound tags like "*Police*" or "[Music]".
        parameters.suppress_nst = true

        // The C strings must outlive whisper_full, so the call happens inside both closures.
        let code: Int32 = (language ?? "auto").withCString { languagePointer in
            (prompt ?? "").withCString { promptPointer in
                parameters.language = languagePointer
                parameters.initial_prompt = prompt == nil ? nil : promptPointer
                return samples.withUnsafeBufferPointer { buffer in
                    whisper_full(context, parameters, buffer.baseAddress, Int32(buffer.count))
                }
            }
        }
        guard code == 0 else {
            throw TranscriptionError.inferenceFailed("whisper_full returned \(code)")
        }

        var text = ""
        for index in 0..<whisper_full_n_segments(context) {
            if let segment = whisper_full_get_segment_text(context, index) {
                text += String(cString: segment)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let silenceLoggingOnce: Void = {
        whisper_log_set({ _, _, _ in }, nil)
    }()

    private static func silenceLogging() {
        _ = silenceLoggingOnce
    }
}
