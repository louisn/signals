import Foundation
import Network
#if os(iOS)
import CoreTelephony
import SystemConfiguration.CaptiveNetwork
#endif

/// Polls the *currently associated* network's metadata -- this is
/// deliberately not a WiFi scan. iOS gives third-party apps no API to
/// enumerate nearby SSIDs/BSSIDs (that requires an Apple-granted
/// NEHotspotHelper entitlement rarely issued outside carrier/enterprise
/// apps), and no cell tower IDs are exposed via CoreTelephony. Reading the
/// current SSID additionally requires the Access WiFi Information
/// capability plus location authorization.
public final class NetworkMetadataCapturer: SignalCapturing {
    public weak var delegate: SignalCapturingDelegate?

    public var pollInterval: TimeInterval = 60

    private let deviceID: UUID
    private let locationProvider: () -> LocationTag?
    private var timer: Timer?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.signals.networkMetadataMonitor")
    #if os(iOS)
    private let telephonyInfo = CTTelephonyNetworkInfo()
    #endif

    public init(deviceID: UUID, locationProvider: @escaping () -> LocationTag?) {
        self.deviceID = deviceID
        self.locationProvider = locationProvider
    }

    public func start() {
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            self?.emit()
        }
        pathMonitor.start(queue: monitorQueue)

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.emit()
        }
    }

    public func stop() {
        pathMonitor.cancel()
        timer?.invalidate()
        timer = nil
    }

    private func emit() {
        let payload = currentNetworkMetadata()
        let record = SignalRecord(
            deviceID: deviceID,
            location: locationProvider(),
            payload: .networkMetadata(payload)
        )
        delegate?.signalCapturer(self, didCapture: record)
    }

    private func currentNetworkMetadata() -> NetworkMetadataPayload {
        #if os(iOS)
        let (ssid, bssid) = Self.currentWiFiInfo()
        let carrier = telephonyInfo.serviceSubscriberCellularProviders?.values.first
        let radioTech = telephonyInfo.serviceCurrentRadioAccessTechnology?.values.first
        return NetworkMetadataPayload(
            wifiSSID: ssid,
            wifiBSSID: bssid,
            carrierName: carrier?.carrierName,
            radioTech: radioTech,
            connectionType: connectionTypeDescription()
        )
        #else
        return NetworkMetadataPayload(
            wifiSSID: nil,
            wifiBSSID: nil,
            carrierName: nil,
            radioTech: nil,
            connectionType: connectionTypeDescription()
        )
        #endif
    }

    private func connectionTypeDescription() -> String? {
        let path = pathMonitor.currentPath
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        return nil
    }

    #if os(iOS)
    private static func currentWiFiInfo() -> (ssid: String?, bssid: String?) {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return (nil, nil) }
        for interface in interfaces {
            guard let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: AnyObject] else { continue }
            let ssid = info[kCNNetworkInfoKeySSID as String] as? String
            let bssid = info[kCNNetworkInfoKeyBSSID as String] as? String
            if ssid != nil {
                return (ssid, bssid)
            }
        }
        return (nil, nil)
    }
    #endif
}
