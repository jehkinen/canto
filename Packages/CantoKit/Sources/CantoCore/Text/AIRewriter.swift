import Foundation

/// Rewrites a transcript with an OpenAI chat model according to the selected text mode.
public struct AIRewriter: Sendable {
    public static let model = "gpt-4.1-mini"

    let chat: any ChatCompleting

    public init(chat: any ChatCompleting) {
        self.chat = chat
    }

    public func rewrite(_ transcript: String, mode: TextProcessingMode, style: String?, vocabulary: [String]) async throws -> String {
        let request = ChatCompletionRequest(model: Self.model, temperature: 0.2, messages: [
            ChatMessage(role: "system", content: RewritePrompt.system(mode: mode, style: style, vocabulary: vocabulary)),
            ChatMessage(role: "user", content: RewritePrompt.user(transcript)),
        ])
        let text = Self.sanitize(try await chat.complete(request))
        guard !text.isEmpty else { throw ChatError.emptyResponse }
        return text
    }

    /// Strips what models sometimes wrap the answer in: code fences, the transcript tags, quotes.
    static func sanitize(_ reply: String) -> String {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
            if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        }
        text = text.replacingOccurrences(of: "</?transcript>", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("\"", "\""), ("«", "»"), ("“", "”")] where text.count > 1 && text.hasPrefix(open) && text.hasSuffix(close) {
            let inner = text.dropFirst().dropLast()
            if !inner.contains(open) && !inner.contains(close) {
                text = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }
}
