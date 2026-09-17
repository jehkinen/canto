import Foundation

public struct ChatMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatCompletionRequest: Equatable, Sendable {
    public var model: String
    public var temperature: Double
    public var messages: [ChatMessage]

    public init(model: String, temperature: Double, messages: [ChatMessage]) {
        self.model = model
        self.temperature = temperature
        self.messages = messages
    }
}

public protocol ChatCompleting: Sendable {
    /// The assistant's reply to a chat completion request.
    func complete(_ request: ChatCompletionRequest) async throws -> String
}

public enum ChatError: Error, Equatable, Sendable {
    case authentication
    case quotaExceeded
    case server(Int)
    case network(String)
    case emptyResponse
}

/// OpenAI `chat/completions`. A network error or a 5xx answer is retried once.
public struct OpenAIChatClient: ChatCompleting {
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private let apiKey: String
    private let session: URLSession
    private let retryDelay: Duration

    public init(apiKey: String, session: URLSession) {
        self.init(apiKey: apiKey, session: session, retryDelay: .milliseconds(400))
    }

    init(apiKey: String, session: URLSession, retryDelay: Duration) {
        self.apiKey = apiKey
        self.session = session
        self.retryDelay = retryDelay
    }

    public func complete(_ request: ChatCompletionRequest) async throws -> String {
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(Body(model: request.model, temperature: request.temperature, messages: request.messages))

        for attempt in 1...2 {
            let data: Data
            let status: Int
            do {
                let (body, response) = try await session.data(for: urlRequest)
                data = body
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt == 2 { throw ChatError.network(error.localizedDescription) }
                try await Task.sleep(for: retryDelay)
                continue
            }

            switch status {
            case 200..<300:
                let reply = try? JSONDecoder().decode(Reply.self, from: data)
                let text = reply?.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { throw ChatError.emptyResponse }
                return text
            case 401, 403:
                throw ChatError.authentication
            case 429:
                throw ChatError.quotaExceeded
            case 500..<600 where attempt == 1:
                try await Task.sleep(for: retryDelay)
            default:
                throw ChatError.server(status)
            }
        }
        throw ChatError.network("no response")
    }

    private struct Body: Encodable {
        let model: String
        let temperature: Double
        let messages: [ChatMessage]
    }

    private struct Reply: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }
}
