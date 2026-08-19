import Foundation

public enum SignalType: String, Codable {
    case location
    case bleAdvertisement = "ble_advertisement"
    case networkMetadata = "network_metadata"
}

public struct LocationPayload: Codable, Equatable {
    public var altitude: Double?
    public var speed: Double?
    public var course: Double?
    public var verticalAccuracy: Double?

    public init(altitude: Double? = nil, speed: Double? = nil, course: Double? = nil, verticalAccuracy: Double? = nil) {
        self.altitude = altitude
        self.speed = speed
        self.course = course
        self.verticalAccuracy = verticalAccuracy
    }
}

public struct BLEAdvertisementPayload: Codable, Equatable {
    public var peripheralUUID: String
    public var name: String?
    public var rssi: Int
    public var serviceUUIDs: [String]
    public var txPower: Int?
    /// Set when the advertisement matches a known tracker-tag signature
    /// (see `TrackerTagClassifier`); nil for everything else.
    public var tagType: String?

    private enum CodingKeys: String, CodingKey {
        case peripheralUUID = "peripheral_uuid"
        case name
        case rssi
        case serviceUUIDs = "service_uuids"
        case txPower = "tx_power"
        case tagType = "tag_type"
    }

    public init(peripheralUUID: String, name: String?, rssi: Int, serviceUUIDs: [String], txPower: Int?, tagType: String? = nil) {
        self.peripheralUUID = peripheralUUID
        self.name = name
        self.rssi = rssi
        self.serviceUUIDs = serviceUUIDs
        self.txPower = txPower
        self.tagType = tagType
    }
}

public struct NetworkMetadataPayload: Codable, Equatable {
    public var wifiSSID: String?
    public var wifiBSSID: String?
    public var carrierName: String?
    public var radioTech: String?
    public var connectionType: String?

    private enum CodingKeys: String, CodingKey {
        case wifiSSID = "wifi_ssid"
        case wifiBSSID = "wifi_bssid"
        case carrierName = "carrier_name"
        case radioTech = "radio_tech"
        case connectionType = "connection_type"
    }

    public init(wifiSSID: String?, wifiBSSID: String?, carrierName: String?, radioTech: String?, connectionType: String?) {
        self.wifiSSID = wifiSSID
        self.wifiBSSID = wifiBSSID
        self.carrierName = carrierName
        self.radioTech = radioTech
        self.connectionType = connectionType
    }
}

/// One of the concrete payload shapes a captured signal can carry. Kept as
/// an enum (rather than a protocol/`Any`) so `SignalStore` can serialize and
/// query on `signalType` without runtime type inspection.
public enum SignalPayload: Equatable {
    case location(LocationPayload)
    case bleAdvertisement(BLEAdvertisementPayload)
    case networkMetadata(NetworkMetadataPayload)

    public var signalType: SignalType {
        switch self {
        case .location: return .location
        case .bleAdvertisement: return .bleAdvertisement
        case .networkMetadata: return .networkMetadata
        }
    }

    public func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        switch self {
        case .location(let payload): return try encoder.encode(payload)
        case .bleAdvertisement(let payload): return try encoder.encode(payload)
        case .networkMetadata(let payload): return try encoder.encode(payload)
        }
    }
}
