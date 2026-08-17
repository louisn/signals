import Foundation

public struct RejectedSignal: Decodable {
    public let id: String
    public let reason: String
}

public struct BatchUploadResponse: Decodable {
    public let batchID: String
    public let accepted: [String]
    public let rejected: [RejectedSignal]

    enum CodingKeys: String, CodingKey {
        case batchID = "batch_id"
        case accepted
        case rejected
    }
}

public enum APIClientError: Error {
    case transport(Error)
    case unauthorized
    case server(status: Int)
    case decoding(Error)
}

/// Talks to `POST /v1/signals/batches`. Deliberately thin -- batching,
/// retry/backoff, and queue-state transitions live in `SyncEngine`, which
/// treats this as a stateless request/response call.
public final class APIClient {
    private let baseURL: URL
    private let deviceID: UUID
    private let session: URLSession
    private let keyLock = NSLock()
    private var apiKey: String

    public init(baseURL: URL, deviceID: UUID, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.deviceID = deviceID
        self.apiKey = apiKey
        self.session = session
    }

    /// Called when the device is (re-)provisioned, e.g. via the in-app
    /// provisioning flow, so `SyncEngine` doesn't need to be torn down and
    /// rebuilt just to pick up a new key. Safe to call from any thread --
    /// `uploadBatch` may be reading the key concurrently from the sync
    /// engine's background queue.
    public func updateAPIKey(_ newKey: String) {
        setAPIKey(newKey)
    }

    private func setAPIKey(_ newKey: String) {
        keyLock.lock()
        defer { keyLock.unlock() }
        apiKey = newKey
    }

    private func currentAPIKey() -> String {
        keyLock.lock()
        defer { keyLock.unlock() }
        return apiKey
    }

    public func uploadBatch(_ payload: UploadBatchPayload) async throws -> BatchUploadResponse {
        let currentKey = currentAPIKey()

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/signals/batches"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(currentKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIClientError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.server(status: -1)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIClientError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIClientError.server(status: http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(BatchUploadResponse.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }
}
