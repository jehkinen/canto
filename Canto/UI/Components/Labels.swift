import SwiftUI
import CantoCore

/// Display names shared by the menu bar panel and the settings.
enum Labels {
    static func mode(_ mode: ActivationMode) -> LocalizedStringKey {
        switch mode {
        case .pushToTalk: "Hold to talk"
        case .toggle: "Press to start and stop"
        }
    }

    static func processing(_ mode: TextProcessingMode) -> LocalizedStringKey {
        switch mode {
        case .original: "Original"
        case .basic, .optimization, .structural, .mdStructural: "Basic cleanup"
        }
    }

    static func processingDescription(_ mode: TextProcessingMode) -> LocalizedStringKey {
        switch mode {
        case .original: "The transcript as is, without cleanup."
        case .basic, .optimization, .structural, .mdStructural: "Removes hallucinations, fixes spacing and capitalization."
        }
    }

    static func model(_ kind: WhisperModelKind) -> String {
        switch kind {
        case .base: "Base"
        case .small: "Small"
        case .largeV3Turbo: "Large v3 Turbo"
        case .parakeetV3: "Parakeet v3"
        case .medium: "Medium"
        case .largeV3: "Large v3"
        }
    }

    static func modelDescription(_ kind: WhisperModelKind) -> LocalizedStringKey {
        switch kind {
        case .base: "Fast, good for clear speech"
        case .small: "Balanced speed and accuracy"
        case .largeV3Turbo: "Nearly as accurate as Large, fast on Apple silicon"
        case .parakeetV3: "Fastest, on the Neural Engine; the vocabulary only fixes spelling"
        case .medium: "Accurate, needs a recent Mac"
        case .largeV3: "Most accurate, slowest"
        }
    }

    /// Whisper languages offered in the pickers; `nil` is auto-detect.
    static let languages: [(code: String?, name: String)] = [
        (nil, String(localized: "Detect automatically")),
        ("en", "English"), ("ru", "Русский"), ("uk", "Українська"), ("de", "Deutsch"), ("fr", "Français"),
        ("es", "Español"), ("it", "Italiano"), ("pt", "Português"), ("pl", "Polski"), ("tr", "Türkçe"),
        ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어"),
    ]

    static func language(_ code: String?) -> String {
        languages.first { $0.code == code }?.name ?? code ?? ""
    }
}
