package com.naberconsulting.signals.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkRequest
import android.util.Log
import com.naberconsulting.signals.queue.SignalStore
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random

/**
 * Drives the offline-first upload loop: claims a batch of pending rows,
 * uploads it, and reconciles the queue from the server's per-record
 * accept/reject response. Runs on a single-thread executor so capture threads
 * never block on network I/O -- the Android counterpart to the iOS SyncEngine.
 */
class SyncEngine(
    context: Context,
    private val store: SignalStore,
    private val apiClient: ApiClient,
    private val meta: MetaProvider,
) {
    /** Batch metadata resolved lazily so device_id/app/os stay current. */
    interface MetaProvider {
        fun deviceId(): String
        fun appVersion(): String
        fun osVersion(): String
    }

    /** Fired after each pass (success/failure/no-op) so UI can refresh queue state. */
    var onPassCompleted: (() -> Unit)? = null

    private val appContext = context.applicationContext
    private val executor = Executors.newSingleThreadScheduledExecutor()
    private val connectivity = appContext.getSystemService(ConnectivityManager::class.java)
    @Volatile private var isSyncing = false
    private var attempt = 0

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = triggerSync()
    }

    fun start() {
        val request = NetworkRequest.Builder()
            .addCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        connectivity?.registerNetworkCallback(request, networkCallback)
    }

    fun stop() {
        runCatching { connectivity?.unregisterNetworkCallback(networkCallback) }
    }

    /** All triggers -- connectivity, app foreground, manual "sync now" -- funnel here. */
    fun triggerSync() {
        executor.execute { runSyncLoop() }
    }

    private fun runSyncLoop() {
        if (isSyncing) return
        isSyncing = true
        try {
            while (store.pendingCount() > 0) {
                val batchId = UUID.randomUUID().toString()
                val rows = store.claimBatch(batchId)
                if (rows.isEmpty()) break

                val body = UploadBatchBuilder.build(
                    UploadBatchBuilder.Meta(meta.deviceId(), meta.appVersion(), meta.osVersion(), batchId),
                    rows,
                )
                try {
                    val response = apiClient.uploadBatch(body)
                    attempt = 0
                    store.markUploaded(response.accepted)
                    store.markFailed(response.rejectedIds, permanent = true)
                } catch (e: UnauthorizedException) {
                    // Re-auth is out of scope for the loop; stop rather than
                    // spin against a bad token. Rows revert to pending.
                    store.markFailed(rows.map { it.id }, permanent = false)
                    Log.w(TAG, "upload unauthorized; pausing sync pass")
                    return
                } catch (e: Exception) {
                    store.markFailed(rows.map { it.id }, permanent = false)
                    scheduleRetry(nextBackoffSeconds())
                    Log.w(TAG, "upload failed: ${e.message}; retry scheduled")
                    return
                }
            }
        } finally {
            isSyncing = false
            pruneOldUploaded()
            onPassCompleted?.invoke()
        }
    }

    private fun scheduleRetry(delaySeconds: Double) {
        executor.schedule({ runSyncLoop() }, (delaySeconds * 1000).toLong(), TimeUnit.MILLISECONDS)
    }

    /** Exponential backoff with jitter, base 5s capped at 10min. */
    private fun nextBackoffSeconds(): Double {
        val exponential = min(BACKOFF_CAP, BACKOFF_BASE * 2.0.pow(attempt))
        attempt += 1
        return exponential * Random.nextDouble(0.8, 1.2)
    }

    private fun pruneOldUploaded() {
        store.pruneUploaded(System.currentTimeMillis() - UPLOADED_RETENTION_MS)
    }

    companion object {
        private const val TAG = "SyncEngine"
        private const val BACKOFF_BASE = 5.0
        private const val BACKOFF_CAP = 600.0
        private const val UPLOADED_RETENTION_MS = 48L * 3600 * 1000
    }
}
