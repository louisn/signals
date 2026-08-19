package com.naberconsulting.signals.capture

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.util.Log
import com.naberconsulting.signals.model.LocationTag
import com.naberconsulting.signals.model.SignalRecord
import com.naberconsulting.signals.model.SignalType
import org.json.JSONObject

/**
 * Wraps the framework [LocationManager] (no Play Services dependency). Keeps
 * the freshest fix so the other capturers can tag their observations, and
 * emits `location` signals in their own right.
 */
class LocationCapturer(
    context: Context,
    private val deviceId: String,
    private val emit: SignalEmitter,
) : SignalCapturing {

    private val manager = context.applicationContext
        .getSystemService(Context.LOCATION_SERVICE) as LocationManager

    @Volatile private var latest: Location? = null

    private val listener = LocationListener { location ->
        latest = location
        emit(location.toRecord())
    }

    @SuppressLint("MissingPermission")
    override fun start() {
        try {
            for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                if (manager.isProviderEnabled(provider)) {
                    manager.requestLocationUpdates(provider, MIN_INTERVAL_MS, MIN_DISTANCE_M, listener)
                }
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "location permission not granted: ${e.message}")
        }
    }

    override fun stop() {
        runCatching { manager.removeUpdates(listener) }
    }

    /** The freshest fix as a [LocationTag], for other capturers to attach. */
    fun currentLocationTag(): LocationTag? = latest?.toTag()

    private fun Location.toTag(): LocationTag = LocationTag(
        lat = latitude,
        lon = longitude,
        horizontalAccuracyMeters = if (hasAccuracy()) accuracy.toDouble() else null,
        ageSeconds = (System.currentTimeMillis() - time).coerceAtLeast(0) / 1000.0,
    )

    private fun Location.toRecord(): SignalRecord {
        val payload = JSONObject().apply {
            if (hasAltitude()) put("altitude", altitude)
            if (hasSpeed()) put("speed", speed.toDouble())
            if (hasBearing()) put("course", bearing.toDouble())
            if (hasVerticalAccuracy()) put("vertical_accuracy", verticalAccuracyMeters.toDouble())
        }
        return SignalRecord(
            deviceId = deviceId,
            location = toTag(),
            signalType = SignalType.LOCATION,
            payload = payload,
        )
    }

    companion object {
        private const val TAG = "LocationCapturer"
        private const val MIN_INTERVAL_MS = 5_000L
        private const val MIN_DISTANCE_M = 5f
    }
}
