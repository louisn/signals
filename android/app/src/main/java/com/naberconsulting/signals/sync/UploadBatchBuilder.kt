package com.naberconsulting.signals.sync

import com.naberconsulting.signals.queue.PendingSignalRow
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/**
 * Builds the `POST /v1/signals/batches` request body from a page of claimed
 * rows. Wire-identical to the iOS UploadBatchBuilder so both clients hit the
 * same Go backend contract.
 */
object UploadBatchBuilder {
    data class Meta(
        val deviceId: String,
        val appVersion: String,
        val osVersion: String,
        val batchId: String,
    )

    fun build(meta: Meta, rows: List<PendingSignalRow>): JSONObject {
        val signals = JSONArray()
        for (row in rows) {
            val signal = JSONObject().apply {
                put("id", row.id)
                put("captured_at", Instant.ofEpochMilli(row.capturedAtMillis).toString())
                put("signal_type", row.signalType)
                if (row.lat != null && row.lon != null) {
                    put("location", JSONObject().apply {
                        put("lat", row.lat)
                        put("lon", row.lon)
                        row.horizontalAccuracy?.let { put("horizontal_accuracy_m", it) }
                        row.locationAgeSeconds?.let { put("age_s", it) }
                    })
                }
                put("payload", JSONObject(row.payloadJson))
            }
            signals.put(signal)
        }
        return JSONObject().apply {
            put("device_id", meta.deviceId)
            put("app_version", meta.appVersion)
            put("os_version", meta.osVersion)
            put("batch_id", meta.batchId)
            put("signals", signals)
        }
    }
}
