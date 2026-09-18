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
        case .largeV3Turbo: "Whisper: 99 languages, takes the vocabulary into account while recognizing"
        case .parakeetV3: "Fastest, on the Neural Engine; 25 European languages"
        case .base, .small, .medium, .largeV3: "No longer offered. Delete it to free up space."
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
