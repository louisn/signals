import Foundation
import Network

/// Drives the offline-first upload loop: claims a batch of pending rows,
/// uploads it, and reconciles the queue based on the server's per-record
/// accept/reject response. Runs on its own serial queue so capture threads
/// never block on network I/O.
public final class SyncEngine {
    private let store: SignalStore
    private let apiClient: APIClient
    private var deviceID: UUID
    private let appVersion: String
    private let osVersion: String

    private let syncQueue = DispatchQueue(label: "com.signals.syncEngine")
    private let pathMonitor = NWPathMonitor()
    private var isSyncing = false
    private var backoff = Backoff()

    /// Fired after each sync pass (success, failure, or no-op) so observers
    /// can refresh UI state that depends on the queue -- `triggerSync()`
    /// only dispatches the pass asynchronously and returns immediately, so
    /// polling queue state right after calling it reflects the state from
    /// *before* the pass ran, not after.
    public var onPassCompleted: (() -> Void)?

    /// Plan calls for retaining uploaded rows ~24-48h before pruning, purely
    /// to bound local DB growth independent of upload success rate.
    private let uploadedRetention: TimeInterval = 48 * 3600

    public init(store: SignalStore, apiClient: APIClient, deviceID: UUID, appVersion: String, osVersion: String) {
        self.store = store
        self.apiClient = apiClient
        self.deviceID = deviceID
        self.appVersion = appVersion
        self.osVersion = osVersion
    }

    public func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                self?.triggerSync()
            }
        }
        pathMonitor.start(queue: syncQueue)
    }

    public func stop() {
        pathMonitor.cancel()
    }

    /// Called on app foreground/background-transition, a `BGProcessingTask`
    /// firing, or a manual/debug trigger -- all funnel into the same
    /// serialized sync loop.
    public func triggerSync() {
        syncQueue.async { [weak self] in
            self?.runSyncLoop()
        }
    }

    /// Adopts a device ID from QR/deep-link provisioning. Applied on the sync
    /// queue so it's consistent with `runSyncLoop`'s reads; queued rows then
    /// upload under the new identity (per-row payloads carry no device_id).
    public func updateDeviceID(_ id: UUID) {
        syncQueue.async { [weak self] in
            self?.deviceID = id
        }
    }

    private func runSyncLoop() {
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            pruneOldUploaded()
            onPassCompleted?()
        }

        while let pendingCount = try? store.pendingCount(), pendingCount > 0 {
            let batchID = UUID().uuidString
            guard let rows = try? store.claimBatch(batchID: batchID), !rows.isEmpty else { break }

            let payload = UploadBatchBuilder.build(
                deviceID: deviceID,
                appVersion: appVersion,
                osVersion: osVersion,
                batchID: batchID,
                rows: rows.map {
                    (id: $0.id, capturedAt: $0.capturedAt, signalType: $0.signalType, payloadJSON: $0.payloadJSON,
                     lat: $0.lat, lon: $0.lon, horizontalAccuracy: $0.horizontalAccuracy, locationAgeSeconds: $0.locationAgeSeconds)
                }
            )

            let semaphore = DispatchSemaphore(value: 0)
            var uploadResult: Result<BatchUploadResponse, Error>?
            Task {
                do {
                    uploadResult = .success(try await apiClient.uploadBatch(payload))
                } catch {
                    uploadResult = .failure(error)
                }
                semaphore.signal()
            }
            semaphore.wait()

            switch uploadResult {
            case .success(let response):
                backoff.reset()
                try? store.markUploaded(ids: response.accepted)
                let permanentlyRejected = response.rejected.map(\.id)
                try? store.markFailed(ids: permanentlyRejected, permanent: true)

            case .failure(let error):
                try? store.markFailed(ids: rows.map(\.id), permanent: false)
                if case APIClientError.unauthorized = error {
                    // Re-auth is out of scope for the sync loop -- surface via
                    // a delegate/notification in a future iteration; for now
                    // stop this pass so we don't spin against a bad token.
                    return
                }
                // Schedule the retry instead of blocking this thread on
                // Thread.sleep: blocking would hold `isSyncing` for up to the
                // 10-minute backoff cap, silently swallowing any foreground
                // or manual "sync now" trigger that arrives in the meantime.
                scheduleRetry(after: backoff.next())
                return

            case .none:
                return
            }
        }
    }

    private func scheduleRetry(after delay: TimeInterval) {
        syncQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.triggerSync()
        }
    }

    private func pruneOldUploaded() {
        try? store.pruneUploaded(olderThan: Date().addingTimeInterval(-uploadedRetention))
    }
}

/// Exponential backoff with jitter, base 5s capped at 10min, reset on success.
private struct Backoff {
    private var attempt = 0
    private let base: TimeInterval = 5
    private let cap: TimeInterval = 600

    mutating func next() -> TimeInterval {
        defer { attempt += 1 }
        let exponential = min(cap, base * pow(2, Double(attempt)))
        return exponential * Double.random(in: 0.8...1.2)
    }

    mutating func reset() {
        attempt = 0
    }
}
