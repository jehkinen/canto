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

    /// Downloads a model, reporting progress at most ten times a second. Cancel the task to abort.
    public func download(_ kind: WhisperModelKind, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let expected = Int64(kind.approximateSizeMB) * 1_000_000
        let downloader = ModelDownloader(destination: url(for: kind), expectedBytes: expected, onProgress: progress)
        try await downloader.run(from: kind.downloadURL)
    }
}

public struct DownloadProgress: Equatable, Sendable {
    public var receivedBytes: Int64
    public var totalBytes: Int64

    public init(receivedBytes: Int64, totalBytes: Int64) {
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double {
        totalBytes > 0 ? min(1, Double(receivedBytes) / Double(totalBytes)) : 0
    }
}

/// A download with a session-level delegate: the async `URLSession.download` API does not report
/// progress to its delegate, which left the progress bar standing still.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedBytes: Int64
    private let onProgress: @Sendable (DownloadProgress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var isCancelled = false
    private var fileError: Error?
    private var lastReport = Date.distantPast

    init(destination: URL, expectedBytes: Int64, onProgress: @escaping @Sendable (DownloadProgress) -> Void) {
        self.destination = destination
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }

    func run(from url: URL) async throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.downloadTask(with: url)
                let started = lock.withLock { () -> Bool in
                    guard !isCancelled else { return false }
                    self.continuation = continuation
                    self.task = task
                    return true
                }
                if started {
                    task.resume()
                } else {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let task = lock.withLock {
                isCancelled = true
                return self.task
            }
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        let shouldReport = lock.withLock {
            guard now.timeIntervalSince(lastReport) >= 0.1 else { return false }
            lastReport = now
            return true
        }
        guard shouldReport else { return }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        onProgress(DownloadProgress(receivedBytes: totalBytesWritten, totalBytes: total))
    }

    /// The temporary file is deleted when this returns, so it is moved right here.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
                throw URLError(.badServerResponse)
            }
            // An error page or a cut-off body must not pass for a model.
            try Self.validateModel(at: location, expectedBytes: expectedBytes)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: location)
            } else {
                try FileManager.default.moveItem(at: location, to: destination)
            }
        } catch {
            lock.withLock { fileError = error }
        }
    }

    /// A whisper.cpp model starts with the ggml magic (or GGUF) and is close to its published size.
    static func validateModel(at url: URL, expectedBytes: Int64) throws {
        let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let magic = try handle.read(upToCount: 4) ?? Data()
        let knownMagic = magic == Data("lmgg".utf8) || magic == Data("GGUF".utf8)
        guard knownMagic, size >= expectedBytes / 2 else { throw URLError(.cannotDecodeContentData) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, fileError) = lock.withLock { () -> (CheckedContinuation<Void, Error>?, Error?) in
            defer { self.continuation = nil }
            return (self.continuation, self.fileError)
        }
        if let error = error ?? fileError {
            continuation?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else {
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? expectedBytes
            onProgress(DownloadProgress(receivedBytes: size, totalBytes: size))
            continuation?.resume()
        }
    }
}
