import Foundation

/// Where Canto keeps its models, skills and history.
public enum AppPaths {
    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Canto", isDirectory: true)
    }

    public static var defaultModelsDirectory: URL {
        supportDirectory.appendingPathComponent("models", isDirectory: true)
    }

    public static var skillsDirectory: URL {
        supportDirectory.appendingPathComponent("skills", isDirectory: true)
    }

    public static var historyFile: URL {
        supportDirectory.appendingPathComponent("history.json")
    }

    public static func modelsDirectory(for settings: AppSettings) -> URL {
        if let custom = settings.whisperModelsDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return defaultModelsDirectory
    }
}
