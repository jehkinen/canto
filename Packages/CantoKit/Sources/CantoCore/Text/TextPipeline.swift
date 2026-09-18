import Foundation

public struct ProcessedText: Equatable, Sendable {
    public var text: String
    public var pressEnter: Bool
    /// The AI mode could not be used and the text was cleaned up the basic way instead.
    public var rewriteFallback: Bool
    public var rewriteFallbackReason: String?
    /// Names of the skills that processed the text.
    public var skills: [String]

    public init(text: String, pressEnter: Bool, rewriteFallback: Bool = false, rewriteFallbackReason: String? = nil,
                skills: [String] = []) {
        self.text = text
        self.pressEnter = pressEnter
        self.rewriteFallback = rewriteFallback
        self.rewriteFallbackReason = rewriteFallbackReason
        self.skills = skills
    }
}

/// From raw recognized text to the text that gets inserted: Whisper artifacts, spoken commands,
/// cleanup, numbers, currency and vocabulary are handled here on the Mac; a skill, when one is
/// chosen, then runs on a chat model.
public struct TextPipeline: Sendable {
    let chat: (any ChatCompleting)?
    let skills: SkillStore
    let model: String

    public init(chat: (any ChatCompleting)?, skills: SkillStore, model: String = AIRewriter.model) {
        self.chat = chat
        self.skills = skills
        self.model = model
    }

    public func process(_ raw: String, settings: AppSettings, fallbackLanguage: String) async -> ProcessedText {
        var text = TextCleanup.removeWhisperArtifacts(raw)

        // Before any rewriting, so the phrase is still recognizable.
        let enter = EnterPhrase.strip(text, phrase: settings.pressEnterOnTrigger ? settings.enterTriggerPhrase : nil)
        text = enter.text

        if settings.spokenPunctuation {
            text = TextCleanup.applySpokenPunctuation(text)
        }

        switch settings.textProcessingMode {
        case .original:
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .basic, .optimization, .structural, .mdStructural:
            text = TextCleanup.basic(text)
        }

        text = formatNumbers(text, settings: settings, fallbackLanguage: fallbackLanguage)
        if !settings.vocabulary.isEmpty {
            text = Vocabulary.apply(text, terms: settings.vocabulary)
        }

        var fallbackReason: String?
        var applied: [String] = []
        if !settings.skills.isEmpty, !text.isEmpty {
            // A skill whose file is gone is skipped; the others still run.
            let loaded = skills.load(settings.skills)
            if let chat, !loaded.isEmpty {
                do {
                    text = try await AIRewriter(chat: chat, model: model)
                        .rewrite(text, skills: loaded, vocabulary: settings.vocabulary)
                    applied = loaded.map(\.name)
                    // The model may spell a number out again or bend a term's spelling.
                    text = formatNumbers(text, settings: settings, fallbackLanguage: fallbackLanguage)
                    if !settings.vocabulary.isEmpty {
                        text = Vocabulary.apply(text, terms: settings.vocabulary)
                    }
                } catch {
                    fallbackReason = String(describing: error)
                }
            } else {
                fallbackReason = chat == nil ? "no AI connection" : "skill \(settings.skills.joined(separator: ", ")) not found"
            }
        }

        return ProcessedText(text: text, pressEnter: enter.pressEnter, rewriteFallback: fallbackReason != nil,
                             rewriteFallbackReason: fallbackReason, skills: applied)
    }

    private func formatNumbers(_ text: String, settings: AppSettings, fallbackLanguage: String) -> String {
        var text = text
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
        return text
    }
}
