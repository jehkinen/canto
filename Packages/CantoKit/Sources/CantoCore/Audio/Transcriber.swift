import Foundation

public protocol Transcriber: Sendable {
    /// Returns the raw recognized text for 16 kHz mono audio. `language` is an ISO 639-1 code
    /// or `nil` for auto-detection; `prompt` is context text that biases spelling (see `Vocabulary`).
    func transcribe(_ segment: AudioSegment, language: String?, prompt: String?) async throws -> String
}

public enum TranscriptionError: Error, Equatable, Sendable {
    case apiKeyMissing
    case modelNotFound(String)
    case modelLoadFailed(String)
    case inferenceFailed(String)
    case authentication
    case quotaExceeded
    case server(String)
    case network(String)
    case cancelled
}
