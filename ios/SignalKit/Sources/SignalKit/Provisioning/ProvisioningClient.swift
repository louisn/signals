import Foundation

public struct ProvisioningResponse: Decodable {
    public let deviceID: String
    public let apiKey: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case apiKey = "api_key"
    }
}

public enum ProvisioningError: Error {
    case transport(Error)
    case invalidAdminKey
    case server(status: Int)
    case decoding(Error)
}

/// Talks to the admin-key-protected `POST /v1/devices`. This is a
/// development/ops convenience -- the admin key must never ship in a
/// release build (see `ProvisioningView`'s `#if DEBUG` gating on the
/// consuming side); this client itself has no opinion on that, it just
/// makes the call it's given credentials for.
public final class ProvisioningClient {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Registers `deviceID` (the app's own Keychain-persisted identity) with
    /// the backend. Re-provisioning an already-registered id is safe and
    /// rotates its key rather than failing.
    public func provisionDevice(deviceID: UUID, label: String, adminKey: String) async throws -> ProvisioningResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(adminKey, forHTTPHeaderField: "X-Admin-Key")
        request.httpBody = try JSONEncoder().encode([
            "device_id": deviceID.uuidString,
            "label": label
        ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProvisioningError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProvisioningError.server(status: -1)
        }
        if http.statusCode == 401 {
            throw ProvisioningError.invalidAdminKey
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProvisioningError.server(status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(ProvisioningResponse.self, from: data)
        } catch {
            throw ProvisioningError.decoding(error)
        }
    }
}
