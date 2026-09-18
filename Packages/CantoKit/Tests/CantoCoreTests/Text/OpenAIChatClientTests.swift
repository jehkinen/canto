import Foundation
import Testing
@testable import CantoCore

/// Serves scripted HTTP responses to a URLSession.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [(status: Int, body: String)] = []
    nonisolated(unsafe) static var requestCount = 0
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let next = Self.lock.withLock { () -> (Int, String) in
            Self.requestCount += 1
            return Self.responses.isEmpty ? (500, "") : Self.responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session(_ responses: [(Int, String)]) -> URLSession {
        lock.withLock {
            self.responses = responses.map { (status: $0.0, body: $0.1) }
            requestCount = 0
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite(.serialized)
struct OpenAIChatClientTests {
    static let request = ChatCompletionRequest(model: "m", temperature: 0, messages: [ChatMessage(role: "user", content: "hi")])
    static let ok = #"{"choices":[{"message":{"content":"  Hello  "}}]}"#

    @Test func returnsTrimmedReply() async throws {
        let client = OpenAIChatClient(apiKey: "k", session: StubProtocol.session([(200, Self.ok)]), retryDelay: .zero)
        #expect(try await client.complete(Self.request) == "Hello")
    }

    @Test func retriesServerErrorOnce() async throws {
        let client = OpenAIChatClient(apiKey: "k", session: StubProtocol.session([(502, ""), (200, Self.ok)]), retryDelay: .zero)
        #expect(try await client.complete(Self.request) == "Hello")
        #expect(StubProtocol.requestCount == 2)
    }

    @Test func retriesRateLimitOnce() async throws {
        let client = OpenAIChatClient(apiKey: "k", session: StubProtocol.session([(429, ""), (200, Self.ok)]), retryDelay: .zero)
        #expect(try await client.complete(Self.request) == "Hello")
    }

    @Test func mapsErrors() async {
        await #expect(throws: ChatError.authentication) {
            try await OpenAIChatClient(apiKey: "k", session: StubProtocol.session([(401, "")]), retryDelay: .zero).complete(Self.request)
        }
        let quota = #"{"error":{"code":"insufficient_quota","type":"insufficient_quota"}}"#
        await #expect(throws: ChatError.quotaExceeded) {
            try await OpenAIChatClient(apiKey: "k", session: StubProtocol.session([(429, quota)]), retryDelay: .zero).complete(Self.request)
        }
        await #expect(throws: ChatError.server(429)) {
            try await OpenAIChatClient(apiKey: "k", session: StubProtocol.session([(429, ""), (429, "")]), retryDelay: .zero).complete(Self.request)
        }
        await #expect(throws: ChatError.emptyResponse) {
            try await OpenAIChatClient(apiKey: "k", session: StubProtocol.session([(200, #"{"choices":[]}"#)]), retryDelay: .zero).complete(Self.request)
        }
    }
}
