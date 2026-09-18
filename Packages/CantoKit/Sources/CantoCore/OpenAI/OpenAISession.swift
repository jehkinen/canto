import Foundation

/// URL sessions for OpenAI calls. Each request gets a new connection: VPNs and routers silently drop
/// idle connections, and a request on such a dead connection hangs until it times out.
public enum OpenAISession {
    /// Seconds without any data before a request is abandoned and retried.
    public static let stallTimeout: TimeInterval = 15

    public static func make(totalTimeout: TimeInterval = 60) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = stallTimeout
        configuration.timeoutIntervalForResource = totalTimeout
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}

/// OpenAI's error body: `{"error": {"code": "insufficient_quota", …}}`.
enum OpenAIError {
    /// A 429 because the account is out of credit, as opposed to a rate limit worth retrying.
    static func isQuota(_ body: Data) -> Bool {
        struct Envelope: Decodable {
            struct Detail: Decodable {
                let code: String?
                let type: String?
            }
            let error: Detail
        }
        guard let detail = try? JSONDecoder().decode(Envelope.self, from: body).error else { return false }
        return detail.code == "insufficient_quota" || detail.type == "insufficient_quota"
    }
}
