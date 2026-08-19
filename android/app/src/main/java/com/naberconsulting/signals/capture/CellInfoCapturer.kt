package com.naberconsulting.signals.capture

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.CellIdentityNr
import android.telephony.CellSignalStrengthNr
import android.telephony.TelephonyManager
import android.util.Log
import com.naberconsulting.signals.model.SignalRecord
import com.naberconsulting.signals.model.SignalType
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Enumerates the serving and neighboring cell towers via
 * [TelephonyManager.getAllCellInfo] -- cell identities (MCC/MNC/CI/PCI/TAC)
 * and signal strength. Another observation iOS gives third-party apps no
 * access to. Emitted as a single `cell_info` signal per poll.
 */
class CellInfoCapturer(
    context: Context,
    private val deviceId: String,
    private val locationProvider: LocationProvider,
    private val emit: SignalEmitter,
) : SignalCapturing {

    private val tm = context.applicationContext
        .getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
    private val scheduler = Executors.newSingleThreadScheduledExecutor()

    override fun start() {
        scheduler.scheduleWithFixedDelay(::capture, 0, POLL_INTERVAL_S, TimeUnit.SECONDS)
    }

    override fun stop() {
        runCatching { scheduler.shutdownNow() }
    }

    @SuppressLint("MissingPermission")
    private fun capture() {
        val infos = try {
            tm.allCellInfo
        } catch (e: SecurityException) {
            Log.w(TAG, "cell info denied: ${e.message}"); return
        } ?: return
        if (infos.isEmpty()) return

        val cells = JSONArray()
        for (info in infos) {
            cellToJson(info)?.let { cells.put(it) }
        }
        if (cells.length() == 0) return

        emit(
            SignalRecord(
                deviceId = deviceId,
                location = locationProvider(),
                signalType = SignalType.CELL_INFO,
                payload = JSONObject().apply {
                    put("cell_count", cells.length())
                    put("cells", cells)
                },
            )
        )
    }

    private fun cellToJson(info: CellInfo): JSONObject? {
        // CellInfoNr and friends are API 29+; the && short-circuits so the
        // instanceof never resolves the class on API 26-28 (minSdk).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && info is CellInfoNr) {
            return nrToJson(info)
        }
        val base = JSONObject().put("registered", info.isRegistered)
        return when (info) {
            is CellInfoLte -> base.apply {
                put("type", "lte")
                val id = info.cellIdentity
                putIfValid("mcc", id.mccString?.toIntOrNull())
                putIfValid("mnc", id.mncString?.toIntOrNull())
                putIfValid("ci", id.ci)
                putIfValid("pci", id.pci)
                putIfValid("tac", id.tac)
                put("dbm", info.cellSignalStrength.dbm)
            }
            is CellInfoWcdma -> base.apply {
                put("type", "wcdma")
                val id = info.cellIdentity
                putIfValid("mcc", id.mccString?.toIntOrNull())
                putIfValid("mnc", id.mncString?.toIntOrNull())
                putIfValid("ci", id.cid)
                putIfValid("lac", id.lac)
                put("dbm", info.cellSignalStrength.dbm)
            }
            is CellInfoGsm -> base.apply {
                put("type", "gsm")
                val id = info.cellIdentity
                putIfValid("mcc", id.mccString?.toIntOrNull())
                putIfValid("mnc", id.mncString?.toIntOrNull())
                putIfValid("ci", id.cid)
                putIfValid("lac", id.lac)
                put("dbm", info.cellSignalStrength.dbm)
            }
            else -> null
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.Q)
    private fun nrToJson(info: CellInfoNr): JSONObject = JSONObject().apply {
        put("registered", info.isRegistered)
        put("type", "nr")
        val id = info.cellIdentity as? CellIdentityNr
        putIfValid("mcc", id?.mccString?.toIntOrNull())
        putIfValid("mnc", id?.mncString?.toIntOrNull())
        putIfValid("pci", id?.pci)
        putIfValid("tac", id?.tac)
        (info.cellSignalStrength as? CellSignalStrengthNr)?.let { put("dbm", it.dbm) }
    }

    /** Skips the frequent CellInfo.UNAVAILABLE (Int.MAX_VALUE) sentinel. */
    private fun JSONObject.putIfValid(key: String, value: Int?) {
        if (value != null && value != Int.MAX_VALUE) put(key, value)
    }

    companion object {
        private const val TAG = "CellInfoCapturer"
        private const val POLL_INTERVAL_S = 60L
    }
}
