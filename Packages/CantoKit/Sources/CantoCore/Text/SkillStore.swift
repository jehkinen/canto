import CryptoKit
import Foundation

/// A skill: a Markdown file whose text tells the AI what to do with a transcript, such as
/// clean it up, fix technical terms or translate it. Its name is the `name:` of a front matter
/// block (the format of Claude skills), else the first "# Heading", else the file name.
public struct Skill: Identifiable, Hashable, Sendable {
    public let fileName: String
    public let name: String
    public var id: String { fileName }
}

/// A skill ready to send: its name and its instructions without the heading and front matter.
public struct LoadedSkill: Equatable, Sendable {
    public var name: String
    public var instructions: String

    public init(name: String, instructions: String) {
        self.name = name
        self.instructions = instructions
    }
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

    /// Remembers which bundled skills were already given to the user and in what form, so a
    /// deleted one does not come back and an untouched one can be brought up to date.
    static let offeredFileName = ".bundled-skills"

    /// What to do with a bundled skill in the user's folder.
    enum BundledUpdate: Equatable {
        /// Never offered: copy it.
        case add
        /// The copy Canto made, unchanged by the user, while the bundled one moved on.
        case replace
        /// The user's own file, an already current copy, or one the user deleted.
        case keep
    }

    /// Fingerprints, not texts: what was written last time, what is there now, what Canto ships.
    /// `recorded` is nil when the skill was never offered and empty when an older Canto copied it
    /// without recording what it wrote.
    static func update(recorded: String?, onDisk: String?, bundled: String) -> BundledUpdate {
        guard let onDisk else { return recorded == nil ? .add : .keep }
        guard onDisk != bundled else { return .keep }
        return recorded == onDisk ? .replace : .keep
    }

    /// Creates the folder, adds every bundled skill the user has not seen, and updates the ones
    /// Canto put there and the user never edited. A file the user wrote or changed is never touched.
    public func ensureDirectory() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = directory.appendingPathComponent(Self.offeredFileName)
        var offered = Self.readRecord(record)
        let before = offered
        for source in Self.bundledSkills {
            let name = source.lastPathComponent
            guard let text = try? String(contentsOf: source, encoding: .utf8) else { continue }
            let bundled = Self.fingerprint(text)
            let destination = directory.appendingPathComponent(name)
            let onDisk = (try? String(contentsOf: destination, encoding: .utf8)).map(Self.fingerprint)
            switch Self.update(recorded: offered[name], onDisk: onDisk, bundled: bundled) {
            case .add, .replace:
                try text.write(to: destination, atomically: true, encoding: .utf8)
                offered[name] = bundled
            case .keep:
                // A file that matches what Canto ships can be updated from now on, even if an
                // older Canto copied it without recording anything. Everything else is the user's:
                // it is only remembered, so it is never offered again.
                if offered[name] == nil || (offered[name] == "" && onDisk == bundled) {
                    offered[name] = onDisk == bundled ? bundled : ""
                }
            }
        }
        if offered != before {
            try Self.writeRecord(offered, to: record)
        }
    }

    /// File name to the fingerprint of the text Canto wrote; empty for a file an older Canto
    /// copied before it recorded fingerprints.
    private static func readRecord(_ url: URL) -> [String: String] {
        var record: [String: String] = [:]
        for line in ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard let name = parts.first.map(String.init), !name.isEmpty else { continue }
            record[name] = parts.count == 2 ? String(parts[1]) : ""
        }
        return record
    }

    private static func writeRecord(_ record: [String: String], to url: URL) throws {
        let lines = record.sorted { $0.key < $1.key }.map { name, fingerprint in
            fingerprint.isEmpty ? name : "\(name)\t\(fingerprint)"
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The skills with these file names that are in the folder, in the same order.
    public func load(_ fileNames: [String]) -> [LoadedSkill] {
        fileNames.compactMap { fileName in
            guard let skill = skill(named: fileName), let instructions = instructions(for: fileName) else { return nil }
            return LoadedSkill(name: skill.name, instructions: instructions)
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
