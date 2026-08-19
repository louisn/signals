package com.naberconsulting.signals.model

import org.json.JSONObject
import java.util.UUID

enum class SignalType(val wire: String) {
    LOCATION("location"),
    BLE_ADVERTISEMENT("ble_advertisement"),
    NETWORK_METADATA("network_metadata"),
    WIFI_SCAN("wifi_scan"),
    CELL_INFO("cell_info"),
}

/**
 * Location context attached to every captured signal, whether or not the
 * signal itself is a location fix. [ageSeconds] lets a consumer judge how
 * stale a cached fix is when it's reused for a BLE/Wi-Fi/cell event.
 */
data class LocationTag(
    val lat: Double,
    val lon: Double,
    val horizontalAccuracyMeters: Double?,
    val ageSeconds: Double?,
)

/**
 * A single captured signal, ready to be queued. [id] is generated at capture
 * time (not upload time) so retried uploads stay idempotent server-side --
 * the same client-generated id/batch contract the iOS client relies on.
 */
data class SignalRecord(
    val id: String = UUID.randomUUID().toString(),
    val deviceId: String,
    val capturedAtMillis: Long = System.currentTimeMillis(),
    val location: LocationTag?,
    val signalType: SignalType,
    val payload: JSONObject,
)
