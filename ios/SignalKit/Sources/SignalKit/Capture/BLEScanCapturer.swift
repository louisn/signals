import CoreBluetooth
import Foundation

/// Wraps `CBCentralManager`. Peripheral UUIDs are session-scoped and
/// randomized by iOS -- they are not stable hardware identifiers, so BLE
/// payloads should not be treated as reliable long-term device fingerprints.
///
/// Background discovery only reliably finds peripherals advertising one of
/// `serviceUUIDsToScan`; a `nil`/wildcard scan (all services) is unreliable
/// once the app is backgrounded per Apple's documented behavior. Pass a
/// curated allow-list if background BLE matters for a deployment.
public final class BLEScanCapturer: NSObject, SignalCapturing {
    public weak var delegate: SignalCapturingDelegate?

    /// How often the same peripheral may re-emit a record, to avoid
    /// recording every duplicate advertisement.
    public var perPeripheralThrottle: TimeInterval = 30

    private let deviceID: UUID
    private let serviceUUIDsToScan: [CBUUID]?
    private let locationProvider: () -> LocationTag?
    private lazy var central = CBCentralManager(delegate: self, queue: nil)
    private var lastEmittedAt: [UUID: Date] = [:]

    public init(deviceID: UUID, serviceUUIDsToScan: [CBUUID]? = nil, locationProvider: @escaping () -> LocationTag?) {
        self.deviceID = deviceID
        self.serviceUUIDsToScan = serviceUUIDsToScan
        self.locationProvider = locationProvider
        super.init()
    }

    public func start() {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: serviceUUIDsToScan,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    public func stop() {
        central.stopScan()
    }

    private func shouldEmit(for peripheralID: UUID) -> Bool {
        guard let last = lastEmittedAt[peripheralID] else { return true }
        return Date().timeIntervalSince(last) >= perPeripheralThrottle
    }
}

extension BLEScanCapturer: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            start()
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard shouldEmit(for: peripheral.identifier) else { return }
        lastEmittedAt[peripheral.identifier] = Date()

        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map(\.uuidString) ?? []
        let txPower = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue

        // Overflow UUIDs (services iOS relegates out of the primary list)
        // still identify a tag ecosystem, so include them for classification
        // -- but keep the payload's service_uuids as the primary list only.
        let overflowUUIDs = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID])?
            .map(\.uuidString) ?? []
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data])?
            .reduce(into: [String: Data]()) { $0[$1.key.uuidString] = $1.value } ?? [:]
        let tagType = TrackerTagClassifier.classify(.init(
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            serviceUUIDs: serviceUUIDs + overflowUUIDs,
            serviceData: serviceData
        ))

        let payload = BLEAdvertisementPayload(
            peripheralUUID: peripheral.identifier.uuidString,
            name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name,
            rssi: RSSI.intValue,
            serviceUUIDs: serviceUUIDs,
            txPower: txPower,
            tagType: tagType?.rawValue
        )
        let record = SignalRecord(
            deviceID: deviceID,
            location: locationProvider(),
            payload: .bleAdvertisement(payload)
        )
        delegate?.signalCapturer(self, didCapture: record)
    }
}
