import Foundation

/// OpenAI `audio/transcriptions`: 3 attempts with backoff on 408/429/5xx and network errors. Every
/// attempt uses a new connection and gives up after `OpenAISession.stallTimeout` without data.
public struct OpenAITranscriber: Transcriber {
    static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    static let maxAttempts = 3

    private let apiKey: String
    private let model: String
    private let session: URLSession?

    /// `session` is for tests; by default each attempt opens its own connection.
    public init(apiKey: String, model: String, session: URLSession? = nil) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func transcribe(_ segment: AudioSegment, language: String?, prompt: String?) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriptionError.apiKeyMissing }
        let boundary = "canto-\(UUID().uuidString)"
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        // Nothing comes back while the server works on the audio, which takes longer for long phrases.
        request.timeoutInterval = OpenAISession.stallTimeout + segment.duration / 2
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var fields = [("model", model), ("temperature", "0")]
        if let language { fields.append(("language", language)) }
        if let prompt { fields.append(("prompt", prompt)) }
        // AAC is about ten times smaller than WAV, so long phrases upload much faster.
        let audio = CompressedAudioEncoder.m4a(segment).map { (data: $0, name: "audio.m4a", type: "audio/mp4") }
            ?? (data: WAVEncoder.encode(segment), name: "audio.wav", type: "audio/wav")
        request.httpBody = Self.multipartBody(boundary: boundary, fields: fields, audio: audio.data, fileName: audio.name, contentType: audio.type)

        var delay: UInt64 = 500
        for attempt in 1...Self.maxAttempts {
            try Task.checkCancellation()
            let attemptSession = session ?? OpenAISession.make(totalTimeout: min(90, 20 + segment.duration * 2))
            defer { if session == nil { attemptSession.finishTasksAndInvalidate() } }
            do {
                let (data, response) = try await attemptSession.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                switch status {
                case 200..<300:
                    guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                        throw TranscriptionError.server("unexpected reply: \(String(decoding: data.prefix(200), as: UTF8.self))")
                    }
                    return payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
                case 401, 403:
                    throw TranscriptionError.authentication
                case 429 where OpenAIError.isQuota(data):
                    // Out of credit: retrying will not help.
                    throw TranscriptionError.quotaExceeded
                case 408, 429, 500..<600:
                    if attempt == Self.maxAttempts {
                        throw status == 429 ? TranscriptionError.quotaExceeded : TranscriptionError.server("HTTP \(status)")
                    }
                default:
                    throw TranscriptionError.server(String(decoding: data, as: UTF8.self))
                }
            } catch let error as TranscriptionError {
                throw error
            } catch is CancellationError {
                throw TranscriptionError.cancelled
            } catch {
                if attempt == Self.maxAttempts {
                    throw TranscriptionError.network("failed after \(attempt) attempts: \(error.localizedDescription)")
                }
            }
            try await Task.sleep(nanoseconds: delay * 1_000_000)
            delay = min(delay * 2, 4_000)
        }
        throw TranscriptionError.network("failed after \(Self.maxAttempts) attempts")
    }

    private struct Payload: Decodable {
        let text: String
    }

    static func multipartBody(boundary: String, fields: [(String, String)], audio: Data,
                              fileName: String = "audio.wav", contentType: String = "audio/wav") -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
