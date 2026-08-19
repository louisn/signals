import CoreLocation
import Foundation
import SignalKit
import Combine
import UIKit

/// Composition root for the capture -> queue -> sync pipeline. Owns the
/// capturers and starts/stops them together so there's a single on/off
/// switch backing the app's status indicator and pause control.
@MainActor
final class CaptureController: ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var pendingCount = 0
    /// Distinct tracker devices (by peripheral UUID) classified this session --
    /// deduped so one tag re-advertising isn't counted many times. Session-
    /// scoped; the durable record is the queued signal itself.
    @Published private(set) var trackerTagCount = 0
    private var trackerTagPeripheralIDs = Set<String>()
    /// Whether a device API key is known, from a prior provisioning (this
    /// launch or a past one) -- drives whether `RootView` shows
    /// `ProvisioningView`. Capture and local queuing work regardless; only
    /// upload needs a key.
    @Published private(set) var hasAPIKey: Bool
    @Published private(set) var hasSkippedProvisioning: Bool
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus
    @Published private(set) var hasSkippedBackgroundUpgrade: Bool

    /// True once "When In Use" is granted but "Always" hasn't been decided
    /// yet -- the window where it makes sense to offer the background
    /// upgrade explanation screen before the system prompt.
    var canOfferBackgroundUpgrade: Bool {
        locationAuthorizationStatus == .authorizedWhenInUse && !hasSkippedBackgroundUpgrade
    }

    private static let skippedProvisioningKey = "hasSkippedProvisioning"
    private static let skippedBackgroundUpgradeKey = "hasSkippedBackgroundUpgrade"

    /// Live device identity; adopted from a scanned QR credential via
    /// `applyConnection`. `private(set)` so the QR flow is the only writer.
    private(set) var deviceID: UUID
    private let store: SignalStore
    private let apiClient: APIClient
    private let syncEngine: SyncEngine
    private let backgroundCoordinator: BackgroundTaskCoordinator
    private let locationCapturer: LocationCapturer
    private let bleCapturer: BLEScanCapturer
    private let networkCapturer: NetworkMetadataCapturer
    private var capturers: [SignalCapturing] { [locationCapturer, bleCapturer, networkCapturer] }
    private var didBecomeActiveObserver: NSObjectProtocol?

    init() {
        let deviceID = DeviceIdentity.currentDeviceID()
        self.deviceID = deviceID

        let appSupportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Application Support isn't created for a fresh app container until
        // something writes to it -- SQLite won't create it implicitly.
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let dbPath = appSupportDir.appendingPathComponent("signals.sqlite").path
        // swiftlint:disable:next force_try -- a failed local DB open is unrecoverable at launch
        let store = try! SignalStore(path: dbPath)
        self.store = store

        // A previously-provisioned key (Keychain) takes priority over the
        // env-var override, which exists only as a quick dev-loop shortcut
        // for pointing at a manually-provisioned device without going
        // through the UI.
        let initialAPIKey = APIKeyStore.read() ?? DevConfig.apiKey
        hasAPIKey = !initialAPIKey.isEmpty
        hasSkippedProvisioning = UserDefaults.standard.bool(forKey: Self.skippedProvisioningKey)
        hasSkippedBackgroundUpgrade = UserDefaults.standard.bool(forKey: Self.skippedBackgroundUpgradeKey)
        locationAuthorizationStatus = .notDetermined

        let baseURL = ConnectionStore.baseURL ?? DevConfig.apiBaseURL
        let apiClient = APIClient(baseURL: baseURL, deviceID: deviceID, apiKey: initialAPIKey)
        self.apiClient = apiClient
        let syncEngine = SyncEngine(
            store: store,
            apiClient: apiClient,
            deviceID: deviceID,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            osVersion: UIDevice.current.systemVersion
        )
        self.syncEngine = syncEngine

        // Registration must happen before app launch finishes, so this
        // controller is created eagerly at the App/AppDelegate level rather
        // than lazily behind onboarding -- capture itself still waits for
        // the user to tap Start.
        backgroundCoordinator = BackgroundTaskCoordinator(syncEngine: syncEngine)

        locationCapturer = LocationCapturer(deviceID: deviceID)
        bleCapturer = BLEScanCapturer(deviceID: deviceID) { [weak locationCapturer] in
            locationCapturer?.latestLocation.map {
                LocationTag(
                    lat: $0.coordinate.latitude,
                    lon: $0.coordinate.longitude,
                    horizontalAccuracyMeters: $0.horizontalAccuracy,
                    ageSeconds: Date().timeIntervalSince($0.timestamp)
                )
            }
        }
        networkCapturer = NetworkMetadataCapturer(deviceID: deviceID) { [weak locationCapturer] in
            locationCapturer?.latestLocation.map {
                LocationTag(
                    lat: $0.coordinate.latitude,
                    lon: $0.coordinate.longitude,
                    horizontalAccuracyMeters: $0.horizontalAccuracy,
                    ageSeconds: Date().timeIntervalSince($0.timestamp)
                )
            }
        }

        for capturer in capturers {
            capturer.delegate = self
        }

        locationAuthorizationStatus = locationCapturer.authorizationStatus
        locationCapturer.onAuthorizationChange = { [weak self] status in
            Task { @MainActor in
                self?.handleLocationAuthorizationChange(status)
            }
        }

        syncEngine.onPassCompleted = { [weak self] in
            Task { @MainActor in
                self?.refreshPendingCount()
            }
        }
        syncEngine.start()
        backgroundCoordinator.register()

        // Records captured while backgrounded should flush the moment the
        // app is reopened, not wait for the next connectivity *change* --
        // NWPathMonitor only fires on transitions, so if WiFi/cellular never
        // actually dropped while backgrounded, nothing else would trigger a
        // sync pass until a manual "Sync now" tap.
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.syncNow()
        }

        refreshPendingCount()
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    func start() {
        guard !isCapturing else { return }
        isCapturing = true
        capturers.forEach { $0.start() }
    }

    func pause() {
        guard isCapturing else { return }
        isCapturing = false
        capturers.forEach { $0.stop() }
        backgroundCoordinator.scheduleNextRun()
    }

    func syncNow() {
        syncEngine.triggerSync()
        refreshPendingCount()
    }

    func saveAPIKey(_ key: String) {
        guard !key.isEmpty else { return }
        APIKeyStore.save(key)
        apiClient.updateAPIKey(key)
        hasAPIKey = true
        syncEngine.triggerSync()
    }

    /// Parses a `signals://connect?base=..&device_id=..&key=..` deep link (from
    /// a scanned QR) and adopts it. Returns false for any non-connect or
    /// malformed URL. The QR is opened by the iOS Camera app -- no in-app
    /// scanner, mirroring the Android flow.
    @discardableResult
    func handleConnectURL(_ url: URL) -> Bool {
        guard let link = ConnectLink.parse(url) else { return false }
        applyConnection(base: link.base, deviceID: link.deviceID, apiKey: link.apiKey)
        return true
    }

    /// Adopts a full connection credential: the backend-minted device ID, the
    /// backend base URL, and the device API key -- no secret typed on the device.
    func applyConnection(base: URL, deviceID: UUID, apiKey: String) {
        DeviceIdentity.setCurrentDeviceID(deviceID)
        self.deviceID = deviceID
        ConnectionStore.baseURL = base
        apiClient.updateBaseURL(base)
        syncEngine.updateDeviceID(deviceID)
        saveAPIKey(apiKey)
    }

    func skipProvisioning() {
        hasSkippedProvisioning = true
        UserDefaults.standard.set(true, forKey: Self.skippedProvisioningKey)
    }

    /// Triggers the system "Always" prompt. Call only after the user has
    /// seen the in-app explanation screen -- this is a distinct, separately-
    /// justified ask, not something to bundle into the initial "When In Use"
    /// request.
    func requestBackgroundLocationUpgrade() {
        locationCapturer.requestAlwaysAuthorization()
    }

    func skipBackgroundUpgrade() {
        hasSkippedBackgroundUpgrade = true
        UserDefaults.standard.set(true, forKey: Self.skippedBackgroundUpgradeKey)
    }

    private func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
        locationAuthorizationStatus = status
        if status == .authorizedAlways {
            #if os(iOS)
            locationCapturer.enableBackgroundUpdates()
            #endif
        }
    }

    #if DEBUG
    /// Dev/ops convenience: calls the admin-protected provisioning endpoint
    /// directly from the device. Not available in release builds -- see
    /// `ProvisioningView`'s `#if DEBUG` gating for why.
    func provisionViaAdminKey(adminKey: String, label: String) async throws {
        let response = try await ProvisioningClient(baseURL: DevConfig.apiBaseURL)
            .provisionDevice(deviceID: deviceID, label: label, adminKey: adminKey)

        guard response.deviceID == deviceID.uuidString else {
            // The backend should always honor the client-supplied device_id
            // (see backend/signals-backend's handleCreateDevice); a mismatch
            // means this app is talking to an incompatible/older backend
            // version, and saving the returned key would silently produce
            // permanent 401s on every future sync.
            throw ProvisioningError.server(status: -1)
        }
        saveAPIKey(response.apiKey)
    }
    #endif

    private func refreshPendingCount() {
        pendingCount = (try? store.pendingCount()) ?? 0
    }
}

extension CaptureController: SignalCapturingDelegate {
    nonisolated func signalCapturer(_ capturer: SignalCapturing, didCapture record: SignalRecord) {
        Task { @MainActor in
            try? store.enqueue(record)
            if case .bleAdvertisement(let payload) = record.payload, payload.tagType != nil {
                if trackerTagPeripheralIDs.insert(payload.peripheralUUID).inserted {
                    trackerTagCount = trackerTagPeripheralIDs.count
                }
            }
            refreshPendingCount()
        }
    }
}
