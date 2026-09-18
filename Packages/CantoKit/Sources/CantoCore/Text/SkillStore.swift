import Foundation

/// A skill: a Markdown file whose text tells the AI what to do with a transcript, such as
/// clean it up, fix technical terms or translate it. Its name is the `name:` of a front matter
/// block (the format of Claude skills), else the first "# Heading", else the file name.
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

    /// Remembers which bundled skills were already offered, so a deleted one does not come back.
    static let offeredFileName = ".bundled-skills"

    /// Creates the folder and adds every bundled skill it has not been offered yet, also to a
    /// folder that already existed. A file with the same name is the user's and stays.
    public func ensureDirectory() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = directory.appendingPathComponent(Self.offeredFileName)
        var offered = Set(((try? String(contentsOf: record, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init))
        let before = offered.count
        for source in Self.bundledSkills where !offered.contains(source.lastPathComponent) {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            if !manager.fileExists(atPath: destination.path) {
                try manager.copyItem(at: source, to: destination)
            }
            offered.insert(source.lastPathComponent)
        }
        if offered.count != before {
            try offered.sorted().joined(separator: "\n").write(to: record, atomically: true, encoding: .utf8)
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

    /// The skill's instructions without its front matter and heading, or `nil` when it is missing or empty.
    public func instructions(for fileName: String?) -> String? {
        guard let fileName, !fileName.isEmpty,
              let text = try? String(contentsOf: fileURL(fileName), encoding: .utf8) else { return nil }
        var lines = Self.parse(text).body
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

    /// The front matter's `name:`, else the first "# Heading", else the file name without its extension.
    static func name(of url: URL) -> String {
        let parsed = parse((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        if let name = parsed.frontMatter["name"], !name.isEmpty { return name }
        for line in parsed.body {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            if !trimmed.isEmpty { break }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Splits off a `---` front matter block of `key: value` lines.
    static func parse(_ text: String) -> (frontMatter: [String: String], body: [String]) {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ([:], lines)
        }
        var frontMatter: [String: String] = [:]
        for line in lines[1..<end] {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let value = pair[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            frontMatter[pair[0].trimmingCharacters(in: .whitespaces).lowercased()] = value
        }
        return (frontMatter, Array(lines[(end + 1)...]))
    }
}
