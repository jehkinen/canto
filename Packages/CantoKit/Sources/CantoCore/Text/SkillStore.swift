import Foundation

/// A skill: a Markdown file whose text tells the AI what to do with a transcript, such as
/// clean it up, fix technical terms or translate it. The first "# Heading" is its name.
public struct Skill: Identifiable, Hashable, Sendable {
    public let fileName: String
    public let name: String
    public var id: String { fileName }
}

/// The skills folder. Canto knows only the format; every skill, the bundled ones included,
/// is a file the user can read, change, delete or share.
public struct SkillStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The skills that come with Canto.
    static var bundledSkills: [URL] {
        Bundle.module.urls(forResourcesWithExtension: "md", subdirectory: "Skills") ?? []
    }

    /// Creates the folder and fills it with the bundled skills the first time.
    public func ensureDirectory() throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: directory.path) else { return }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for source in Self.bundledSkills {
            try manager.copyItem(at: source, to: directory.appendingPathComponent(source.lastPathComponent))
        }
    }

    public func list() -> [Skill] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { Skill(fileName: $0.lastPathComponent, name: Self.name(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func skill(named fileName: String?) -> Skill? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let url = fileURL(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Skill(fileName: url.lastPathComponent, name: Self.name(of: url))
    }

    /// The skill's instructions without its heading, or `nil` when it is missing or empty.
    public func instructions(for fileName: String?) -> String? {
        guard let fileName, !fileName.isEmpty,
              let text = try? String(contentsOf: fileURL(fileName), encoding: .utf8) else { return nil }
        var lines = text.components(separatedBy: .newlines)
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].trimmingCharacters(in: .whitespaces).hasPrefix("# ") {
            lines.remove(at: first)
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    /// Copies a Markdown file into the skills folder, replacing a skill with the same file name.
    public func importSkill(from source: URL) throws -> Skill {
        guard source.pathExtension.lowercased() == "md" else { throw CocoaError(.fileReadUnsupportedScheme) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        if source.standardizedFileURL != destination.standardizedFileURL {
            let data = try Data(contentsOf: source)
            try data.write(to: destination, options: .atomic)
        }
        return Skill(fileName: destination.lastPathComponent, name: Self.name(of: destination))
    }

    /// Only files inside the skills folder.
    private func fileURL(_ fileName: String) -> URL {
        directory.appendingPathComponent((fileName as NSString).lastPathComponent)
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
