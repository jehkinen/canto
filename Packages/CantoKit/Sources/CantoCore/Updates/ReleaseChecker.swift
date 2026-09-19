import Foundation

/// A published Canto release on GitHub.
public struct AppRelease: Equatable, Sendable {
    public var version: String
    /// The release page, where the DMG and the notes are.
    public var pageURL: URL

    public init(version: String, pageURL: URL) {
        self.version = version
        self.pageURL = pageURL
    }
}

/// Asks GitHub for the latest Canto release. Only the public releases API is contacted, with no
/// data about the user; the app shows a download link and never installs anything by itself.
public enum ReleaseChecker {
    public static let latestURL = URL(string: "https://api.github.com/repos/jehkinen/canto/releases/latest")!

    public static func latest(session: URLSession = .shared) async throws -> AppRelease {
        var request = URLRequest(url: latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> AppRelease {
        struct Payload: Decodable {
            var tag_name: String
            var html_url: URL
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return AppRelease(version: version, pageURL: payload.html_url)
    }

    /// Whether a version like "1.0.10" is newer than "1.0.9", comparing number by number.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let new = parts(candidate), old = parts(current)
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
