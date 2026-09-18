import Foundation

public struct TranscriptEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var text: String
    public var duration: TimeInterval
    public var provider: TranscriptionProvider
    public var processingMode: TextProcessingMode
    public var appName: String?
    /// Seconds from the end of the phrase to the text being inserted.
    public var latency: TimeInterval?
    /// The name of the skill that processed the text.
    public var skill: String?
    /// What the model heard, before punctuation, numbers and the skill; kept when it differs from `text`.
    public var recognized: String?

    public init(id: UUID = UUID(), date: Date = Date(), text: String, duration: TimeInterval,
                provider: TranscriptionProvider, processingMode: TextProcessingMode, appName: String?,
                latency: TimeInterval? = nil, skill: String? = nil, recognized: String? = nil) {
        self.id = id
        self.date = date
        self.text = text
        self.duration = duration
        self.provider = provider
        self.processingMode = processingMode
        self.appName = appName
        self.latency = latency
        self.skill = skill
        self.recognized = recognized
    }
}

/// The most recent transcripts, newest first, persisted as JSON.
public struct TranscriptHistory: Sendable {
    public static let limit = 200

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> [TranscriptEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TranscriptEntry].self, from: data)) ?? []
    }

    public func save(_ entries: [TranscriptEntry]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Array(entries.prefix(Self.limit))).write(to: fileURL, options: .atomic)
    }
}
