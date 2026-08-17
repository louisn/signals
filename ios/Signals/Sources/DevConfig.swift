import Foundation

/// Dev-loop shortcut: reads the backend base URL / API key from scheme
/// environment variables so a dev build can skip `ProvisioningView`
/// entirely. Defaults to the hosted Fly dev backend, since that's reachable
/// from a real device without any local setup; override
/// `SIGNALS_API_BASE_URL` in the Xcode scheme to point at a locally running
/// backend instead (`http://localhost:8080` on the Simulator, or the Mac's
/// LAN IP on a real device -- localhost on-device means the device itself).
enum DevConfig {
    static var apiBaseURL: URL {
        let raw = ProcessInfo.processInfo.environment["SIGNALS_API_BASE_URL"] ?? "https://signals-api-dev.fly.dev"
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
