package com.naberconsulting.signals.capture

import android.content.Context
import android.os.Build
import com.naberconsulting.signals.DevConfig
import com.naberconsulting.signals.model.SignalRecord
import com.naberconsulting.signals.model.SignalType
import com.naberconsulting.signals.provisioning.ApiKeyStore
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
    val deviceId: String = DeviceIdentity.currentDeviceId(appContext)

    private val store = SignalStore(appContext)
    private val apiClient = ApiClient(DevConfig.apiBaseUrl, ApiKeyStore.read(appContext))

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

    private val _tagSightings = MutableStateFlow(0)
    val tagSightings: StateFlow<Int> = _tagSightings.asStateFlow()

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
            _tagSightings.value += 1
        }
        refreshPendingCount()
    }

    private fun refreshPendingCount() {
        _pendingCount.value = store.pendingCount()
    }
}
