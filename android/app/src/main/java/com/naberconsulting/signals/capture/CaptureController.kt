package com.naberconsulting.signals.capture

import android.content.Context
import android.os.Build
import com.naberconsulting.signals.DevConfig
import com.naberconsulting.signals.model.SignalRecord
import com.naberconsulting.signals.model.SignalType
import com.naberconsulting.signals.provisioning.ApiKeyStore
import com.naberconsulting.signals.provisioning.BaseUrlStore
import com.naberconsulting.signals.provisioning.DeviceIdentity
import com.naberconsulting.signals.provisioning.ProvisioningClient
import com.naberconsulting.signals.queue.SignalStore
import com.naberconsulting.signals.sync.ApiClient
import com.naberconsulting.signals.sync.SyncEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

/**
 * Composition root for the capture -> queue -> sync pipeline -- the Android
 * counterpart to the iOS CaptureController. Owns the capturers and drives
 * them together behind one on/off switch, and exposes queue/UI state as flows.
 */
class CaptureController(context: Context) {

    private val appContext = context.applicationContext

    /** Live device identity; adopted from a scanned credential via [applyConnection]. */
    @Volatile var deviceId: String = DeviceIdentity.currentDeviceId(appContext)
        private set

    private val store = SignalStore(appContext)
    private val apiClient = ApiClient(
        BaseUrlStore.read(appContext) ?: DevConfig.apiBaseUrl,
        ApiKeyStore.read(appContext),
    )

    private val syncEngine = SyncEngine(
        appContext, store, apiClient,
        object : SyncEngine.MetaProvider {
            override fun deviceId() = deviceId
            override fun appVersion() = "1.0"
            override fun osVersion() = Build.VERSION.RELEASE ?: "0"
        },
    )

    private val locationCapturer = LocationCapturer(appContext, deviceId, ::onCapture)
    private val locationProvider: LocationProvider = { locationCapturer.currentLocationTag() }

    private val capturers: List<SignalCapturing> = listOf(
        locationCapturer,
        BleScanCapturer(appContext, deviceId, locationProvider, ::onCapture),
        WifiScanCapturer(appContext, deviceId, locationProvider, ::onCapture),
        NetworkMetadataCapturer(appContext, deviceId, locationProvider, ::onCapture),
        CellInfoCapturer(appContext, deviceId, locationProvider, ::onCapture),
    )

    private val _isCapturing = MutableStateFlow(false)
    val isCapturing: StateFlow<Boolean> = _isCapturing.asStateFlow()

    private val _pendingCount = MutableStateFlow(0)
    val pendingCount: StateFlow<Int> = _pendingCount.asStateFlow()

    /// Distinct tracker devices (by advertiser MAC) classified this session --
    /// deduped so one tag re-advertising isn't counted many times.
    private val _trackerTagCount = MutableStateFlow(0)
    val trackerTagCount: StateFlow<Int> = _trackerTagCount.asStateFlow()
    private val trackerTagMacs = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    private val _hasApiKey = MutableStateFlow(ApiKeyStore.read(appContext).isNotEmpty())
    val hasApiKey: StateFlow<Boolean> = _hasApiKey.asStateFlow()

    init {
        syncEngine.onPassCompleted = { refreshPendingCount() }
        syncEngine.start()
        refreshPendingCount()
    }

    fun start() {
        if (_isCapturing.value) return
        _isCapturing.value = true
        capturers.forEach { it.start() }
    }

    fun stop() {
        if (!_isCapturing.value) return
        _isCapturing.value = false
        capturers.forEach { it.stop() }
    }

    fun syncNow() {
        syncEngine.triggerSync()
        refreshPendingCount()
    }

    /**
     * Adopts a full connection credential from a scanned `signals://connect`
     * deep link: the backend-minted device id, the backend base URL, and the
     * device api key. No secret is typed on the device.
     */
    fun applyConnection(base: String, newDeviceId: String, apiKey: String) {
        DeviceIdentity.setDeviceId(appContext, newDeviceId)
        deviceId = newDeviceId
        BaseUrlStore.save(appContext, base)
        apiClient.updateBaseUrl(base)
        saveApiKey(apiKey)
    }

    fun saveApiKey(key: String) {
        if (key.isEmpty()) return
        ApiKeyStore.save(appContext, key)
        apiClient.updateApiKey(key)
        _hasApiKey.value = true
        syncEngine.triggerSync()
    }

    /**
     * Dev/ops convenience: registers this device against the admin-protected
     * endpoint directly. The admin key is user-typed, never embedded.
     */
    suspend fun provisionViaAdminKey(adminKey: String, label: String) {
        val response = withContext(Dispatchers.IO) {
            ProvisioningClient(DevConfig.apiBaseUrl).provisionDevice(deviceId, label, adminKey)
        }
        saveApiKey(response.apiKey)
    }

    private fun onCapture(record: SignalRecord) {
        store.enqueue(record)
        if (record.signalType == SignalType.BLE_ADVERTISEMENT && record.payload.has("tag_type")) {
            val mac = record.payload.optString("mac_address")
            if (mac.isNotEmpty() && trackerTagMacs.add(mac)) {
                _trackerTagCount.value = trackerTagMacs.size
            }
        }
        refreshPendingCount()
    }

    private fun refreshPendingCount() {
        _pendingCount.value = store.pendingCount()
    }
}
