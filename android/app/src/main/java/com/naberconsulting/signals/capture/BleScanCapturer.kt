package com.naberconsulting.signals.capture

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import com.naberconsulting.signals.model.SignalRecord
import com.naberconsulting.signals.model.SignalType
import org.json.JSONArray
import org.json.JSONObject

/**
 * Wraps the BLE scanner. Unlike iOS -- which replaces the peripheral's
 * hardware MAC with a session-random UUID -- Android's [ScanResult] exposes
 * the advertiser's real advertised MAC (`device.address`), which this capturer
 * records as the primary identifier. Advertisements are also run through
 * [TrackerTagClassifier] for AirTag/Tile/SmartTag/etc. tagging.
 */
class BleScanCapturer(
    context: Context,
    private val deviceId: String,
    private val locationProvider: LocationProvider,
    private val emit: SignalEmitter,
) : SignalCapturing {

    private val scanner = (context.applicationContext
        .getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
        .adapter?.bluetoothLeScanner

    private val lastEmittedAt = HashMap<String, Long>()
    private val perDeviceThrottleMs = 30_000L

    private val callback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) = handle(result)
        override fun onBatchScanResults(results: MutableList<ScanResult>) = results.forEach(::handle)
        override fun onScanFailed(errorCode: Int) {
            Log.w(TAG, "BLE scan failed: $errorCode")
        }
    }

    @SuppressLint("MissingPermission")
    override fun start() {
        val scanner = scanner ?: run { Log.w(TAG, "no BLE scanner (adapter off/absent)"); return }
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            scanner.startScan(null, settings, callback)
        } catch (e: SecurityException) {
            Log.w(TAG, "BLUETOOTH_SCAN not granted: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    override fun stop() {
        runCatching { scanner?.stopScan(callback) }
    }

    private fun handle(result: ScanResult) {
        val address = result.device.address ?: return
        val now = System.currentTimeMillis()
        if (now - (lastEmittedAt[address] ?: 0) < perDeviceThrottleMs) return
        lastEmittedAt[address] = now

        val record = result.scanRecord
        val serviceUuids = record?.serviceUuids?.mapNotNull { it.short16() } ?: emptyList()
        val tagType = TrackerTagClassifier.classify(
            TrackerTagClassifier.Advertisement(
                manufacturerData = record?.appleManufacturerData(),
                serviceUuids = serviceUuids,
                serviceData = record?.serviceData16() ?: emptyMap(),
            )
        )

        val payload = JSONObject().apply {
            put("mac_address", address)
            put("address_type", addressTypeOf(address))
            put("rssi", result.rssi)
            put("service_uuids", JSONArray(serviceUuids))
            record?.deviceName?.let { put("name", it) }
            record?.txPowerLevel?.takeIf { it != Int.MIN_VALUE }?.let { put("tx_power", it) }
            tagType?.let { put("tag_type", it.wire) }
        }
        emit(
            SignalRecord(
                deviceId = deviceId,
                location = locationProvider(),
                signalType = SignalType.BLE_ADVERTISEMENT,
                payload = payload,
            )
        )
    }

    /**
     * Best-effort static/random-vs-public inference from the MAC's two most
     * significant bits, per the BLE address-type convention -- avoids the
     * API-34 getAddressType() call and the BLUETOOTH_CONNECT it needs.
     */
    private fun addressTypeOf(mac: String): String {
        val firstOctet = mac.substringBefore(':').toIntOrNull(16) ?: return "unknown"
        return if ((firstOctet and 0xC0) == 0xC0) "random_static" else "public_or_random"
    }

    /**
     * Reconstructs Apple's manufacturer block (company-id bytes prepended) so
     * the shared classifier sees the same [0x4C,0x00,type,...] shape it does
     * on iOS -- Android hands manufacturer data back keyed by company id with
     * those two bytes stripped.
     */
    private fun ScanRecord.appleManufacturerData(): ByteArray? {
        val payload = getManufacturerSpecificData(APPLE_COMPANY_ID) ?: return null
        return byteArrayOf(
            (APPLE_COMPANY_ID and 0xFF).toByte(),
            ((APPLE_COMPANY_ID shr 8) and 0xFF).toByte(),
        ) + payload
    }

    private fun ScanRecord.serviceData16(): Map<String, ByteArray> =
        serviceData?.entries?.mapNotNull { (uuid, bytes) ->
            uuid.short16()?.let { it to bytes }
        }?.toMap() ?: emptyMap()

    /** The 16-bit assigned-number portion of a Bluetooth-base UUID, uppercase hex. */
    private fun ParcelUuid.short16(): String? {
        val s = uuid.toString()
        return if (s.length >= 8) s.substring(4, 8).uppercase() else null
    }

    companion object {
        private const val TAG = "BleScanCapturer"
        private const val APPLE_COMPANY_ID = 0x004C
    }
}
