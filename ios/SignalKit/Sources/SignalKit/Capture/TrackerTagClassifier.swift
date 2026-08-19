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
    /// Length byte of the "separated" offline-finding frame (0x19 = 25 bytes,
    /// the rotating public key). The "nearby" frame is far shorter (~0x02).
    private static let appleFindMySeparatedMinLen: UInt8 = 0x19
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
        if isAppleFindMySeparated(ad.manufacturerData) { return .appleFindMy }
        if isGoogleFindMyDevice(ad.serviceData) { return .googleFindMyDevice }
        return nil
    }

    private static func classifyByServiceUUID(_ uuids: [String]) -> TrackerTagType? {
        uuids.lazy.compactMap { serviceUUIDTags[$0.uppercased()] }.first
    }

    /// A *separated* Find My device -- an unattended tracker broadcasting its
    /// rotating public key while away from its owner. Keyed on Apple company
    /// ID + offline-finding type (0x12) + the long "separated" length byte.
    ///
    /// Deliberately excludes the short "nearby" 0x12 frame: that is broadcast
    /// by *every* Apple device in the Find My network (iPhones, Macs, AirPods
    /// near their owner), so flagging it produced huge false-positive "tracker"
    /// counts. Other Apple types (AirPods pairing 0x07, Handoff 0x0C) differ.
    private static func isAppleFindMySeparated(_ manufacturerData: Data?) -> Bool {
        guard let data = manufacturerData, data.count >= 4 else { return false }
        return data[data.startIndex] == appleCompanyID.0
            && data[data.startIndex + 1] == appleCompanyID.1
            && data[data.startIndex + 2] == appleFindMyPayloadType
            && data[data.startIndex + 3] >= appleFindMySeparatedMinLen
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
