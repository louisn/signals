package com.naberconsulting.signals.queue

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.naberconsulting.signals.model.SignalRecord

/** A persisted queue row, mirroring the upload envelope. */
data class PendingSignalRow(
    val id: String,
    val capturedAtMillis: Long,
    val signalType: String,
    val payloadJson: String,
    val lat: Double?,
    val lon: Double?,
    val horizontalAccuracy: Double?,
    val locationAgeSeconds: Double?,
)

/**
 * Offline-first queue for captured signals, backed by SQLite. A single
 * `pending_signals` table with a `status` column drives the whole
 * pending -> uploading -> uploaded/failed lifecycle that [SyncEngine] depends
 * on -- the Android counterpart to the iOS GRDB-backed SignalStore.
 */
class SignalStore(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    init {
        // Rows left in `uploading` by a run that was killed mid-upload have no
        // in-flight tracking once the process exits -- requeue them so they
        // aren't silently stuck forever.
        recoverStaleUploads()
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE pending_signals (
                id TEXT PRIMARY KEY NOT NULL,
                captured_at INTEGER NOT NULL,
                signal_type TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                lat REAL,
                lon REAL,
                horizontal_accuracy REAL,
                location_age_seconds REAL,
                status TEXT NOT NULL DEFAULT 'pending',
                batch_id TEXT,
                attempt_count INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX idx_pending_status_captured ON pending_signals (status, captured_at)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Queue rows are ephemeral (pruned within 48h); a schema change can
        // safely drop and recreate rather than migrate.
        db.execSQL("DROP TABLE IF EXISTS pending_signals")
        onCreate(db)
    }

    private fun recoverStaleUploads() {
        writableDatabase.execSQL(
            "UPDATE pending_signals SET status = 'pending', batch_id = NULL WHERE status = 'uploading'"
        )
    }

    fun enqueue(record: SignalRecord) {
        val values = ContentValues().apply {
            put("id", record.id)
            put("captured_at", record.capturedAtMillis)
            put("signal_type", record.signalType.wire)
            put("payload_json", record.payload.toString())
            record.location?.let {
                put("lat", it.lat)
                put("lon", it.lon)
                it.horizontalAccuracyMeters?.let { v -> put("horizontal_accuracy", v) }
                it.ageSeconds?.let { v -> put("location_age_seconds", v) }
            }
            put("status", "pending")
            put("created_at", System.currentTimeMillis())
        }
        writableDatabase.insertWithOnConflict(
            "pending_signals", null, values, SQLiteDatabase.CONFLICT_IGNORE
        )
    }

    /**
     * Claims up to [limit] pending rows, stamping them with [batchId] and
     * moving them to `uploading` in one transaction so a crash mid-upload
     * doesn't leave them stuck in `pending`.
     */
    fun claimBatch(batchId: String, limit: Int = 500): List<PendingSignalRow> {
        val db = writableDatabase
        val rows = mutableListOf<PendingSignalRow>()
        db.beginTransaction()
        try {
            db.query(
                "pending_signals", null, "status = 'pending'", null,
                null, null, "captured_at ASC", limit.toString()
            ).use { c ->
                while (c.moveToNext()) rows.add(c.toRow())
            }
            if (rows.isNotEmpty()) {
                val ids = rows.joinToString(",") { "'${it.id}'" }
                val values = ContentValues().apply {
                    put("status", "uploading")
                    put("batch_id", batchId)
                }
                db.update("pending_signals", values, "id IN ($ids)", null)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return rows
    }

    fun markUploaded(ids: List<String>) {
        if (ids.isEmpty()) return
        val placeholders = ids.joinToString(",") { "?" }
        writableDatabase.execSQL(
            "UPDATE pending_signals SET status = 'uploaded' WHERE id IN ($placeholders)",
            ids.toTypedArray()
        )
    }

    /**
     * Reverts rejected/failed rows to `pending` (transient) or `failed`
     * (permanent, or after [maxAttempts]) so the next sync pass picks up the
     * right ones.
     */
    fun markFailed(ids: List<String>, permanent: Boolean, maxAttempts: Int = 20) {
        if (ids.isEmpty()) return
        val db = writableDatabase
        db.beginTransaction()
        try {
            for (id in ids) {
                db.query(
                    "pending_signals", arrayOf("attempt_count"), "id = ?", arrayOf(id),
                    null, null, null
                ).use { c ->
                    if (!c.moveToFirst()) return@use
                    val attempts = c.getInt(0) + 1
                    val status = if (permanent || attempts >= maxAttempts) "failed" else "pending"
                    val values = ContentValues().apply {
                        put("attempt_count", attempts)
                        put("status", status)
                        putNull("batch_id")
                    }
                    db.update("pending_signals", values, "id = ?", arrayOf(id))
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** Hard-deletes `uploaded` rows older than [cutoffMillis], bounding DB growth. */
    fun pruneUploaded(cutoffMillis: Long) {
        writableDatabase.execSQL(
            "DELETE FROM pending_signals WHERE status = 'uploaded' AND captured_at < ?",
            arrayOf<Any>(cutoffMillis)
        )
    }

    fun pendingCount(): Int =
        readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM pending_signals WHERE status = 'pending'", null
        ).use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }

    private fun android.database.Cursor.toRow(): PendingSignalRow {
        fun optDouble(name: String): Double? {
            val i = getColumnIndexOrThrow(name)
            return if (isNull(i)) null else getDouble(i)
        }
        return PendingSignalRow(
            id = getString(getColumnIndexOrThrow("id")),
            capturedAtMillis = getLong(getColumnIndexOrThrow("captured_at")),
            signalType = getString(getColumnIndexOrThrow("signal_type")),
            payloadJson = getString(getColumnIndexOrThrow("payload_json")),
            lat = optDouble("lat"),
            lon = optDouble("lon"),
            horizontalAccuracy = optDouble("horizontal_accuracy"),
            locationAgeSeconds = optDouble("location_age_seconds"),
        )
    }

    companion object {
        private const val DB_NAME = "signals.db"
        private const val DB_VERSION = 1
    }
}
