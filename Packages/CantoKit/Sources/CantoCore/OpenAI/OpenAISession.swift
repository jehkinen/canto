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
