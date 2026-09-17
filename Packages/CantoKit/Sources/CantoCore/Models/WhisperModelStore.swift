import Foundation

public struct WhisperModelInfo: Identifiable, Equatable, Sendable {
    public var kind: WhisperModelKind
    public var url: URL
    public var isInstalled: Bool
    public var id: WhisperModelKind { kind }
}

/// Lists and downloads ggml Whisper models from Hugging Face.
public struct WhisperModelStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for kind: WhisperModelKind) -> URL {
        directory.appendingPathComponent(kind.fileName)
    }

    public func isInstalled(_ kind: WhisperModelKind) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url(for: kind).path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    public func models() -> [WhisperModelInfo] {
        WhisperModelKind.allCases.map { WhisperModelInfo(kind: $0, url: url(for: $0), isInstalled: isInstalled($0)) }
    }

    public func delete(_ kind: WhisperModelKind) throws {
        try FileManager.default.removeItem(at: url(for: kind))
    }

    /// Downloads a model, reporting progress (0…1) at most every 200 ms. Cancel the task to abort.
    public func download(_ kind: WhisperModelKind, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let delegate = DownloadProgressDelegate(onProgress: progress)
        let (temporary, response) = try await URLSession.shared.download(from: kind.downloadURL, delegate: delegate)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: temporary)
            throw URLError(.badServerResponse)
        }
        let destination = url(for: kind)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        progress(1)
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var lastReport = Date.distantPast

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, Date().timeIntervalSince(lastReport) >= 0.2 else { return }
        lastReport = Date()
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
