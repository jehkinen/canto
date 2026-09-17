import Foundation

/// A Markdown file with extra instructions for the AI modes, such as tone or terminology.
public struct AIStyle: Identifiable, Hashable, Sendable {
    public let fileName: String
    public let name: String
    public var id: String { fileName }
}

public struct StyleStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    static let exampleFileName = "Friendly and concise.md"
    static let example = """
        # Friendly and concise

        Write in a warm, friendly tone. Prefer short sentences and simple words.
        Keep greetings and sign-offs short. Do not add emoji.
        """

    /// Creates the folder, with an example style the first time.
    public func ensureDirectory() throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: directory.path) else { return }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.example.write(to: directory.appendingPathComponent(Self.exampleFileName), atomically: true, encoding: .utf8)
    }

    public func list() -> [AIStyle] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { AIStyle(fileName: $0.lastPathComponent, name: Self.name(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The style's instructions, or `nil` when it is missing or empty.
    public func instructions(for fileName: String?) -> String? {
        guard let fileName, !fileName.isEmpty else { return nil }
        // Only files inside the styles folder.
        let url = directory.appendingPathComponent((fileName as NSString).lastPathComponent)
        let text = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// Copies a Markdown file into the styles folder, replacing a style with the same file name.
    public func importStyle(from source: URL) throws -> AIStyle {
        guard source.pathExtension.lowercased() == "md" else { throw CocoaError(.fileReadUnsupportedScheme) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        if source.standardizedFileURL != destination.standardizedFileURL {
            let data = try Data(contentsOf: source)
            try data.write(to: destination, options: .atomic)
        }
        return AIStyle(fileName: destination.lastPathComponent, name: Self.name(of: destination))
    }

    /// The first "# Heading" in the file, or the file name without its extension.
    static func name(of url: URL) -> String {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            if !trimmed.isEmpty { break }
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
