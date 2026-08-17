import XCTest
@testable import SignalKit

/// Stubs network responses so these tests can simulate connectivity
/// loss/recovery deterministically -- toggling actual airplane mode inside
/// an automated test run isn't reliable or scriptable.
private final class StubURLProtocol: URLProtocol {
    static var shouldFail = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if Self.shouldFail {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        struct OutgoingSignal: Decodable { let id: String }
        struct OutgoingBatch: Decodable {
            let batchID: String
            let signals: [OutgoingSignal]
            enum CodingKeys: String, CodingKey { case batchID = "batch_id"; case signals }
        }

        let body = request.httpBody ?? Data()
        let batch = try? JSONDecoder().decode(OutgoingBatch.self, from: body)
        let responseBody: [String: Any] = [
            "batch_id": batch?.batchID ?? "",
            "accepted": batch?.signals.map(\.id) ?? [],
            "rejected": [],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: responseBody)) ?? Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class SyncEngineTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.shouldFail = false
        super.tearDown()
    }

    private func makeEngine(store: SignalStore, deviceID: UUID) -> SyncEngine {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let apiClient = APIClient(
            baseURL: URL(string: "https://example.invalid")!,
            deviceID: deviceID,
            apiKey: "test-key",
            session: URLSession(configuration: config)
        )
        return SyncEngine(store: store, apiClient: apiClient, deviceID: deviceID, appVersion: "1", osVersion: "1")
    }

    private func makeLocationRecord(deviceID: UUID) -> SignalRecord {
        SignalRecord(
            deviceID: deviceID,
            location: LocationTag(lat: 1, lon: 2, horizontalAccuracyMeters: 5, ageSeconds: 0),
            payload: .location(LocationPayload(altitude: 10, speed: 1, course: 90, verticalAccuracy: 3))
        )
    }

    /// Models "airplane mode is on": every upload attempt fails at the
    /// transport level. The record must stay queued, not be dropped.
    func testConnectivityLossRequeuesRecordInsteadOfLosingIt() throws {
        let store = try SignalStore(path: ":memory:")
        let deviceID = UUID()
        try store.enqueue(makeLocationRecord(deviceID: deviceID))
        let engine = makeEngine(store: store, deviceID: deviceID)

        StubURLProtocol.shouldFail = true
        engine.triggerSync()

        // markFailed runs synchronously before the backoff sleep, so the
        // requeue is observable well before the sleep completes.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, (try? store.pendingCount()) != 1 {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(try store.pendingCount(), 1, "a failed upload must requeue the record, not drop it")
    }

    /// Models "airplane mode turns back off": a prior failure is followed by
    /// a successful attempt, and the record should end up uploaded.
    func testConnectivityRestoredUploadsSuccessfully() throws {
        let store = try SignalStore(path: ":memory:")
        let deviceID = UUID()
        try store.enqueue(makeLocationRecord(deviceID: deviceID))
        let engine = makeEngine(store: store, deviceID: deviceID)

        StubURLProtocol.shouldFail = false
        engine.triggerSync()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, (try? store.pendingCount()) != 0 {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(try store.pendingCount(), 0)
        // Uploaded, not just claimed -- re-claiming should find nothing left.
        XCTAssertEqual(try store.claimBatch(batchID: "verify").count, 0)
    }

    /// A failed pass schedules its own retry after a multi-second backoff,
    /// but must not hold `isSyncing` for that whole window -- otherwise a
    /// manual "sync now" tap (or the foreground trigger) arriving during
    /// that window would silently no-op instead of getting a real attempt.
    func testManualTriggerDuringPendingBackoffStillSyncs() throws {
        let store = try SignalStore(path: ":memory:")
        let deviceID = UUID()
        try store.enqueue(makeLocationRecord(deviceID: deviceID))
        let engine = makeEngine(store: store, deviceID: deviceID)

        StubURLProtocol.shouldFail = true
        engine.triggerSync()

        let requeued = Date().addingTimeInterval(2)
        while Date() < requeued, (try? store.pendingCount()) != 1 {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertEqual(try store.pendingCount(), 1, "failed pass should have requeued the record already")

        StubURLProtocol.shouldFail = false
        engine.triggerSync()

        // The backoff base delay is 5s -- succeeding well inside 1s proves
        // this manual call wasn't blocked behind the scheduled auto-retry.
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, (try? store.pendingCount()) != 0 {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertEqual(try store.pendingCount(), 0, "a manual retry must not be blocked by a pending automatic backoff retry")
    }

    func testOnPassCompletedFiresAfterEachPass() throws {
        let store = try SignalStore(path: ":memory:")
        let deviceID = UUID()
        try store.enqueue(makeLocationRecord(deviceID: deviceID))
        let engine = makeEngine(store: store, deviceID: deviceID)

        let completed = expectation(description: "pass completed")
        engine.onPassCompleted = { completed.fulfill() }

        StubURLProtocol.shouldFail = false
        engine.triggerSync()

        wait(for: [completed], timeout: 2)
    }
}
