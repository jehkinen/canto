import Foundation

public struct ProcessedText: Equatable, Sendable {
    public var text: String
    public var pressEnter: Bool
    /// The AI mode could not be used and the text was cleaned up the basic way instead.
    public var rewriteFallback: Bool
    public var rewriteFallbackReason: String?

    public init(text: String, pressEnter: Bool, rewriteFallback: Bool = false, rewriteFallbackReason: String? = nil) {
        self.text = text
        self.pressEnter = pressEnter
        self.rewriteFallback = rewriteFallback
        self.rewriteFallbackReason = rewriteFallbackReason
    }
}

/// From raw recognized text to the text that gets inserted.
public struct TextPipeline: Sendable {
    let chat: (any ChatCompleting)?
    let styles: StyleStore

    public init(chat: (any ChatCompleting)?, styles: StyleStore) {
        self.chat = chat
        self.styles = styles
    }

    public func process(_ raw: String, settings: AppSettings, fallbackLanguage: String) async -> ProcessedText {
        var text = TextCleanup.removeWhisperArtifacts(raw)

        // Before any rewriting, so the phrase is still recognizable.
        let enter = EnterPhrase.strip(text, phrase: settings.pressEnterOnTrigger ? settings.enterTriggerPhrase : nil)
        text = enter.text

        if settings.spokenPunctuation {
            text = TextCleanup.applySpokenPunctuation(text)
        }

        var fallbackReason: String?
        switch settings.textProcessingMode {
        case .original:
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .basic:
            text = TextCleanup.basic(text)
        case .optimization, .structural, .mdStructural:
            if let chat, !text.isEmpty {
                do {
                    text = try await AIRewriter(chat: chat).rewrite(
                        text,
                        mode: settings.textProcessingMode,
                        style: styles.instructions(for: settings.aiStyle),
                        vocabulary: settings.vocabulary
                    )
                } catch {
                    fallbackReason = String(describing: error)
                    text = TextCleanup.basic(text)
                }
            } else {
                if chat == nil { fallbackReason = "no API key" }
                text = TextCleanup.basic(text)
            }
        }

        switch settings.numberFormat {
        case .asHeard:
            break
        case .digits:
            text = SpokenNumbers.toDigits(text)
        case .words:
            text = NumberWords.apply(text, language: settings.effectiveLanguage(fallback: fallbackLanguage))
        }
        if settings.currencySymbols {
            text = SpokenNumbers.currencySymbols(text)
        }
        if !settings.vocabulary.isEmpty {
            text = Vocabulary.apply(text, terms: settings.vocabulary)
        }

        return ProcessedText(text: text, pressEnter: enter.pressEnter, rewriteFallback: fallbackReason != nil,
                             rewriteFallbackReason: fallbackReason)
    }
}
