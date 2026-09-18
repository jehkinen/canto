import Foundation

/// Runs a skill on a transcript with a chat model: OpenAI or an OpenAI-compatible local server.
public struct AIRewriter: Sendable {
    /// The OpenAI model skills use.
    public static let model = "gpt-4.1-mini"

    let chat: any ChatCompleting
    let model: String

    public init(chat: any ChatCompleting, model: String = AIRewriter.model) {
        self.chat = chat
        self.model = model
    }

    public func rewrite(_ transcript: String, skillName: String, instructions: String, vocabulary: [String]) async throws -> String {
        let request = ChatCompletionRequest(model: model, temperature: 0.2, messages: [
            ChatMessage(role: "system", content: RewritePrompt.system(skillName: skillName, instructions: instructions,
                                                                      vocabulary: vocabulary)),
            ChatMessage(role: "user", content: RewritePrompt.user(transcript)),
        ])
        let text = Self.sanitize(try await chat.complete(request))
        guard !text.isEmpty else { throw ChatError.emptyResponse }
        return text
    }

    /// Strips what models sometimes wrap the answer in: code fences, the transcript tags, quotes.
    static func sanitize(_ reply: String) -> String {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only a reply that is one fenced block as a whole; Markdown with code inside stays as it is.
        if text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6,
           text.dropFirst(3).dropLast(3).range(of: "```") == nil {
            text = text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
            text = String(text.dropLast(3))
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
