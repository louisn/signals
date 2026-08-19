package com.naberconsulting.signals.capture

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.telephony.TelephonyManager
import android.util.Log
import com.naberconsulting.signals.model.SignalRecord
import com.naberconsulting.signals.model.SignalType
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * The connected-network snapshot: currently-associated Wi-Fi (SSID + BSSID),
 * carrier, radio tech, and connection type. Mirrors the iOS
 * NetworkMetadataCapturer, but Android can populate `wifi_bssid` (the
 * connected AP's MAC), which iOS leaves null.
 */
class NetworkMetadataCapturer(
    context: Context,
    private val deviceId: String,
    private val locationProvider: LocationProvider,
    private val emit: SignalEmitter,
) : SignalCapturing {

    private val appContext = context.applicationContext
    private val scheduler = Executors.newSingleThreadScheduledExecutor()

    override fun start() {
        scheduler.scheduleWithFixedDelay(::capture, 0, POLL_INTERVAL_S, TimeUnit.SECONDS)
    }

    override fun stop() {
        runCatching { scheduler.shutdownNow() }
    }

    @SuppressLint("MissingPermission")
    private fun capture() {
        val payload = JSONObject()

        try {
            val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            val info = wifi.connectionInfo
            @Suppress("DEPRECATION")
            val ssid = info?.ssid?.trim('"')?.takeIf { it.isNotEmpty() && it != "<unknown ssid>" }
            @Suppress("DEPRECATION")
            val bssid = info?.bssid?.takeIf { it != "02:00:00:00:00:00" }
            ssid?.let { payload.put("wifi_ssid", it) }
            bssid?.let { payload.put("wifi_bssid", it) }
        } catch (e: Exception) {
            Log.w(TAG, "wifi info unavailable: ${e.message}")
        }

        try {
            val tm = appContext.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            tm.networkOperatorName?.takeIf { it.isNotEmpty() }?.let { payload.put("carrier_name", it) }
            payload.put("radio_tech", radioTechName(tm.dataNetworkType))
        } catch (e: Exception) {
            Log.w(TAG, "telephony info unavailable: ${e.message}")
        }

        payload.put("connection_type", activeConnectionType())

        emit(
            SignalRecord(
                deviceId = deviceId,
                location = locationProvider(),
                signalType = SignalType.NETWORK_METADATA,
                payload = payload,
            )
        )
    }

    private fun activeConnectionType(): String {
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return "none"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
    }

    private fun radioTechName(type: Int): String = when (type) {
        TelephonyManager.NETWORK_TYPE_NR -> "5g_nr"
        TelephonyManager.NETWORK_TYPE_LTE -> "lte"
        TelephonyManager.NETWORK_TYPE_HSPAP,
        TelephonyManager.NETWORK_TYPE_HSPA,
        TelephonyManager.NETWORK_TYPE_UMTS -> "wcdma"
        TelephonyManager.NETWORK_TYPE_EDGE,
        TelephonyManager.NETWORK_TYPE_GPRS -> "gsm"
        TelephonyManager.NETWORK_TYPE_UNKNOWN -> "unknown"
        else -> "other_$type"
    }

    companion object {
        private const val TAG = "NetworkMetadataCapturer"
        private const val POLL_INTERVAL_S = 60L
    }
}
