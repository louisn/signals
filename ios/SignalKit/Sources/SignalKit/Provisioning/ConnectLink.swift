import Foundation

/// A parsed `signals://connect?base=..&device_id=..&key=..` deep link, as
/// produced by the backend's QR provisioning page and opened by the iOS
/// Camera app. A pure value type so parsing is unit-testable without a running
/// app or the (simulator-unreliable) URL delivery path.
public struct ConnectLink: Equatable {
    public let base: URL
    public let deviceID: UUID
    public let apiKey: String

    public init(base: URL, deviceID: UUID, apiKey: String) {
        self.base = base
        self.deviceID = deviceID
        self.apiKey = apiKey
    }

    /// Returns nil for any non-`signals://connect` or malformed URL (missing/
    /// empty key, unparseable device_id or base), so callers can safely ignore
    /// unrelated URLs.
    public static func parse(_ url: URL) -> ConnectLink? {
        guard url.scheme == "signals", url.host == "connect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let baseString = value("base"), let base = URL(string: baseString),
              let idString = value("device_id"), let id = UUID(uuidString: idString),
              let key = value("key"), !key.isEmpty else { return nil }
        return ConnectLink(base: base, deviceID: id, apiKey: key)
    }
}
