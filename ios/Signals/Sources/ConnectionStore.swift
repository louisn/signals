import Foundation

/// Persists the backend base URL adopted from a scanned QR credential, so it
/// survives relaunch. Unset until a QR connect overrides the `DevConfig`
/// default -- the iOS counterpart to Android's BaseUrlStore.
enum ConnectionStore {
    private static let baseURLKey = "connectionBaseURL"

    static var baseURL: URL? {
        get { UserDefaults.standard.string(forKey: baseURLKey).flatMap { URL(string: $0) } }
        set { UserDefaults.standard.set(newValue?.absoluteString, forKey: baseURLKey) }
    }
}
