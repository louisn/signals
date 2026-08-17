import Foundation

/// Dev-loop shortcut: reads the backend base URL / API key from scheme
/// environment variables so a dev build can skip `ProvisioningView`
/// entirely. On the Simulator, `http://localhost:8080` reaches a locally
/// running backend directly; on a real device, point `SIGNALS_API_BASE_URL`
/// at the Mac's LAN IP instead (localhost on-device means the device
/// itself, not your Mac).
enum DevConfig {
    static var apiBaseURL: URL {
        let raw = ProcessInfo.processInfo.environment["SIGNALS_API_BASE_URL"] ?? "http://localhost:8080"
        guard let url = URL(string: raw) else {
            fatalError("SIGNALS_API_BASE_URL is not a valid URL: \(raw)")
        }
        return url
    }

    /// Empty until a device has been provisioned against the backend, either
    /// via `ProvisioningView` or by pasting a key from `POST /v1/devices`
    /// into the `SIGNALS_API_KEY` scheme environment variable.
    static var apiKey: String {
        ProcessInfo.processInfo.environment["SIGNALS_API_KEY"] ?? ""
    }
}
