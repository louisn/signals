import Foundation
import GRDB

public enum PendingSignalStatus: String, Codable, DatabaseValueConvertible {
    case pending
    case uploading
    case uploaded
    case failed
}

/// The persisted row shape, mirroring the upload envelope so a batch can be
/// built directly from a page of rows without further transformation.
struct PendingSignalRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pending_signals"

    var id: String
    var deviceID: String
    var capturedAt: Date
    var signalType: String
    var payloadJSON: Data
    var lat: Double?
    var lon: Double?
    var horizontalAccuracy: Double?
    var locationAgeSeconds: Double?
    var status: PendingSignalStatus
    var batchID: String?
    var attemptCount: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, deviceID = "device_id", capturedAt = "captured_at", signalType = "signal_type"
        case payloadJSON = "payload_json", lat, lon
        case horizontalAccuracy = "horizontal_accuracy", locationAgeSeconds = "location_age_seconds"
        case status, batchID = "batch_id", attemptCount = "attempt_count", createdAt = "created_at"
    }
}

/// Offline-first queue for captured signals, backed by SQLite via GRDB.
/// Chosen over Core Data (too much ceremony for a flat high-frequency queue
/// table) and a raw file-based queue (weak status tracking, no atomic
/// partial-batch acknowledgement). A single `pending_signals` table with a
/// `status` column drives the whole pending -> uploading -> uploaded/failed
/// lifecycle that `SyncEngine` depends on.
public final class SignalStore {
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createPendingSignals") { db in
            try db.create(table: "pending_signals") { t in
                t.column("id", .text).primaryKey()
                t.column("device_id", .text).notNull()
                t.column("captured_at", .datetime).notNull()
                t.column("signal_type", .text).notNull()
                t.column("payload_json", .blob).notNull()
                t.column("lat", .double)
                t.column("lon", .double)
                t.column("horizontal_accuracy", .double)
                t.column("location_age_seconds", .double)
                t.column("status", .text).notNull().defaults(to: PendingSignalStatus.pending.rawValue)
                t.column("batch_id", .text)
                t.column("attempt_count", .integer).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_pending_signals_status_captured", on: "pending_signals", columns: ["status", "captured_at"])
        }
        return migrator
    }

    public func enqueue(_ record: SignalRecord) throws {
        let row = try PendingSignalRow(
            id: record.id.uuidString,
            deviceID: record.deviceID.uuidString,
            capturedAt: record.capturedAt,
            signalType: record.payload.signalType.rawValue,
            payloadJSON: record.payload.encodedData(),
            lat: record.location?.lat,
            lon: record.location?.lon,
            horizontalAccuracy: record.location?.horizontalAccuracyMeters,
            locationAgeSeconds: record.location?.ageSeconds,
            status: .pending,
            batchID: nil,
            attemptCount: 0,
            createdAt: Date()
        )
        try dbQueue.write { db in
            try row.insert(db)
        }
    }

    /// Claims up to `limit` pending rows for upload, stamping them with
    /// `batchID` and moving them to `.uploading` so a crash mid-upload
    /// doesn't leave them silently stuck in `.pending` forever -- callers
    /// should call `markFailed` on timeout/crash recovery to requeue them.
    func claimBatch(batchID: String, limit: Int = 500) throws -> [PendingSignalRow] {
        try dbQueue.write { db in
            let rows = try PendingSignalRow
                .filter(Column("status") == PendingSignalStatus.pending.rawValue)
                .order(Column("captured_at"))
                .limit(limit)
                .fetchAll(db)

            for var row in rows {
                row.status = .uploading
                row.batchID = batchID
                try row.update(db)
            }
            return rows
        }
    }

    func markUploaded(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE pending_signals SET status = ? WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ","))) ",
                arguments: StatementArguments([PendingSignalStatus.uploaded.rawValue] + ids)
            )
        }
    }

    /// Reverts rejected/failed rows to `.pending` (transient) or `.failed`
    /// (permanent, after `maxAttempts`) so the sync engine's next pass
    /// picks up the right ones.
    func markFailed(ids: [String], permanent: Bool, maxAttempts: Int = 20) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            for id in ids {
                guard var row = try PendingSignalRow.fetchOne(db, key: id) else { continue }
                row.attemptCount += 1
                row.status = (permanent || row.attemptCount >= maxAttempts) ? .failed : .pending
                row.batchID = nil
                try row.update(db)
            }
        }
    }

    /// Hard-deletes `.uploaded` rows older than `olderThan`, bounding local
    /// DB growth independent of upload success rate.
    public func pruneUploaded(olderThan cutoff: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM pending_signals WHERE status = ? AND captured_at < ?",
                arguments: [PendingSignalStatus.uploaded.rawValue, cutoff]
            )
        }
    }

    public func pendingCount() throws -> Int {
        try dbQueue.read { db in
            try PendingSignalRow.filter(Column("status") == PendingSignalStatus.pending.rawValue).fetchCount(db)
        }
    }
}
