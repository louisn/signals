import XCTest
@testable import SignalKit

final class SignalStoreTests: XCTestCase {
    private func makeStore() throws -> SignalStore {
        try SignalStore(path: ":memory:")
    }

    private func makeFileBackedStore() throws -> (store: SignalStore, path: String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite").path
        return (try SignalStore(path: path), path)
    }

    private func makeLocationRecord(deviceID: UUID = UUID()) -> SignalRecord {
        SignalRecord(
            deviceID: deviceID,
            location: LocationTag(lat: 1, lon: 2, horizontalAccuracyMeters: 5, ageSeconds: 0),
            payload: .location(LocationPayload(altitude: 10, speed: 1, course: 90, verticalAccuracy: 3))
        )
    }

    func testEnqueueIncreasesPendingCount() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.pendingCount(), 0)

        try store.enqueue(makeLocationRecord())

        XCTAssertEqual(try store.pendingCount(), 1)
    }

    func testClaimBatchMovesRowsOutOfPending() throws {
        let store = try makeStore()
        try store.enqueue(makeLocationRecord())
        try store.enqueue(makeLocationRecord())

        let claimed = try store.claimBatch(batchID: "batch-1")

        XCTAssertEqual(claimed.count, 2)
        XCTAssertEqual(try store.pendingCount(), 0)
    }

    func testMarkUploadedThenPruneRemovesRow() throws {
        let store = try makeStore()
        let record = makeLocationRecord()
        try store.enqueue(record)
        let claimed = try store.claimBatch(batchID: "batch-1")

        try store.markUploaded(ids: claimed.map(\.id))
        try store.pruneUploaded(olderThan: Date().addingTimeInterval(3600))

        // Pruned rows are gone entirely -- re-claiming should find nothing.
        XCTAssertEqual(try store.claimBatch(batchID: "batch-2").count, 0)
    }

    func testMarkFailedTransientRequeuesAsPending() throws {
        let store = try makeStore()
        try store.enqueue(makeLocationRecord())
        let claimed = try store.claimBatch(batchID: "batch-1")

        try store.markFailed(ids: claimed.map(\.id), permanent: false)

        XCTAssertEqual(try store.pendingCount(), 1)
    }

    func testMarkFailedPermanentDoesNotRequeue() throws {
        let store = try makeStore()
        try store.enqueue(makeLocationRecord())
        let claimed = try store.claimBatch(batchID: "batch-1")

        try store.markFailed(ids: claimed.map(\.id), permanent: true)

        XCTAssertEqual(try store.pendingCount(), 0)
    }

    /// A row claimed into `.uploading` right before the app is killed (or
    /// crashes) has no in-flight tracking once the process exits -- the next
    /// launch must requeue it rather than leaving it stuck forever.
    func testStaleUploadingRowsAreRecoveredOnNextLaunch() throws {
        let (store, path) = try makeFileBackedStore()
        try store.enqueue(makeLocationRecord())
        _ = try store.claimBatch(batchID: "batch-1")
        XCTAssertEqual(try store.pendingCount(), 0, "claimed row should have left .pending")

        let recoveredStore = try SignalStore(path: path)

        XCTAssertEqual(try recoveredStore.pendingCount(), 1)
    }
}
