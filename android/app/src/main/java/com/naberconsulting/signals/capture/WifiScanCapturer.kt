package com.naberconsulting.signals.capture

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.naberconsulting.signals.model.SignalRecord
import com.naberconsulting.signals.model.SignalType
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Enumerates *nearby* Wi-Fi access points with their BSSIDs (the AP's MAC),
 * SSID, signal, and channel -- the headline capability iOS has no API for.
 * One `wifi_scan` signal is emitted per completed scan, carrying the whole AP
 * list. Note Android heavily throttles startScan() (~4/2 min foreground), so
 * this paces its own rescans and also relays passive results the OS delivers.
 */
class WifiScanCapturer(
    context: Context,
    private val deviceId: String,
    private val locationProvider: LocationProvider,
    private val emit: SignalEmitter,
) : SignalCapturing {

    private val appContext = context.applicationContext
    private val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    @Volatile private var running = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = emitResults()
    }

    override fun start() {
        if (running) return
        running = true
        ContextCompat.registerReceiver(
            appContext, receiver,
            IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        scheduler.scheduleWithFixedDelay(::requestScan, 0, RESCAN_INTERVAL_S, TimeUnit.SECONDS)
    }

    override fun stop() {
        running = false
        runCatching { appContext.unregisterReceiver(receiver) }
    }

    @SuppressLint("MissingPermission")
    private fun requestScan() {
        try {
            @Suppress("DEPRECATION")
            wifi.startScan()
        } catch (e: SecurityException) {
            Log.w(TAG, "wifi scan permission not granted: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    private fun emitResults() {
        val results = try {
            wifi.scanResults
        } catch (e: SecurityException) {
            Log.w(TAG, "scanResults denied: ${e.message}"); return
        }
        if (results.isEmpty()) return

        val aps = JSONArray()
        for (r in results) {
            aps.put(JSONObject().apply {
                put("bssid", r.BSSID)
                @Suppress("DEPRECATION")
                put("ssid", r.SSID)
                put("rssi", r.level)
                put("frequency_mhz", r.frequency)
                put("channel_width", r.channelWidth)
                put("capabilities", r.capabilities)
            })
        }
        emit(
            SignalRecord(
                deviceId = deviceId,
                location = locationProvider(),
                signalType = SignalType.WIFI_SCAN,
                payload = JSONObject().apply {
                    put("access_point_count", aps.length())
                    put("access_points", aps)
                },
            )
        )
    }

    companion object {
        private const val TAG = "WifiScanCapturer"
        private const val RESCAN_INTERVAL_S = 30L
    }
}
