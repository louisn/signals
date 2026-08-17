import Foundation

/// v1 stopgap for backend connectivity: the in-app provisioning flow is
/// deferred (plan build-order step 12), so a dev build points at a
/// manually-provisioned API key for one device, set here or via the
/// `SIGNALS_API_BASE_URL` / `SIGNALS_API_KEY` scheme environment variables
/// so a key never has to be hardcoded into source.
enum DevConfig {
    static var apiBaseURL: URL {
        let raw = ProcessInfo.processInfo.environment["SIGNALS_API_BASE_URL"] ?? "http://localhost:8080"
        guard let url = URL(string: raw) else {
            fatalError("SIGNALS_API_BASE_URL is not a valid URL: \(raw)")
        }
        return url
    }

    /// Empty until a device has been provisioned against the backend (see
    /// `backend/signals-backend`'s `POST /v1/devices`) and its key pasted in
    /// via the `SIGNALS_API_KEY` environment variable.
    static var apiKey: String {
        ProcessInfo.processInfo.environment["SIGNALS_API_KEY"] ?? ""
    }
}
