import Foundation

/// Classifies a BLE advertisement as a known tracker tag ("smart tag")
/// from its advertised signatures. Best-effort: it identifies the tag
/// *ecosystem*, not the individual tag -- peripheral UUIDs are
/// session-random and most of these products rotate their advertised
/// identifiers by design.
///
/// Note Apple Find My accessories (AirTags) advertise only manufacturer
/// data, no service UUID, so they can't be picked up by a background
/// service-UUID allow-list scan -- foreground wildcard scanning is what
/// finds them.
public enum TrackerTagType: String {
    case appleFindMy = "apple_find_my"
    case tile = "tile"
    case samsungSmartTag = "samsung_smarttag"
    case chipolo = "chipolo"
    case googleFindMyDevice = "google_find_my_device"
}

public enum TrackerTagClassifier {
    private static let appleCompanyID: (UInt8, UInt8) = (0x4C, 0x00)
    private static let appleFindMyPayloadType: UInt8 = 0x12
    private static let eddystoneFMDNFrameType: UInt8 = 0x40

    private static let serviceUUIDTags: [String: TrackerTagType] = [
        "FEED": .tile,
        "FD5A": .samsungSmartTag,
        "FE33": .chipolo,
    ]

    public struct Advertisement {
        public var manufacturerData: Data?
        public var serviceUUIDs: [String]
        /// Keyed by service UUID string, as `CBUUID.uuidString` renders it.
        public var serviceData: [String: Data]

        public init(manufacturerData: Data?, serviceUUIDs: [String], serviceData: [String: Data]) {
            self.manufacturerData = manufacturerData
            self.serviceUUIDs = serviceUUIDs
            self.serviceData = serviceData
        }
    }

    public static func classify(_ ad: Advertisement) -> TrackerTagType? {
        if let tag = classifyByServiceUUID(ad.serviceUUIDs) { return tag }
        if isAppleFindMy(ad.manufacturerData) { return .appleFindMy }
        if isGoogleFindMyDevice(ad.serviceData) { return .googleFindMyDevice }
        return nil
    }

    private static func classifyByServiceUUID(_ uuids: [String]) -> TrackerTagType? {
        uuids.lazy.compactMap { serviceUUIDTags[$0.uppercased()] }.first
    }

    /// Find My network (offline-finding) frames: Apple company ID followed
    /// by payload type 0x12. Type bytes for other Apple advertisements
    /// (AirPods pairing, Handoff, etc.) differ, so this doesn't flag every
    /// Apple device in range.
    private static func isAppleFindMy(_ manufacturerData: Data?) -> Bool {
        guard let data = manufacturerData, data.count >= 3 else { return false }
        return data[data.startIndex] == appleCompanyID.0
            && data[data.startIndex + 1] == appleCompanyID.1
            && data[data.startIndex + 2] == appleFindMyPayloadType
    }

    /// Google's Find My Device network piggybacks on the Eddystone service
    /// UUID (0xFEAA) with its own frame type, distinct from classic
    /// Eddystone frames (0x00/0x10/0x20/0x30).
    private static func isGoogleFindMyDevice(_ serviceData: [String: Data]) -> Bool {
        guard let frame = serviceData.first(where: { $0.key.uppercased() == "FEAA" })?.value,
              let frameType = frame.first else { return false }
        return frameType == eddystoneFMDNFrameType
    }
}
