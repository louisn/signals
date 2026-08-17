import Foundation

public struct UploadSignalLocation: Encodable {
    let lat: Double
    let lon: Double
    let horizontalAccuracyM: Double?
    let ageS: Double?

    enum CodingKeys: String, CodingKey {
        case lat, lon
        case horizontalAccuracyM = "horizontal_accuracy_m"
        case ageS = "age_s"
    }
}

public struct UploadSignal: Encodable {
    let id: String
    let capturedAt: Date
    let signalType: String
    let location: UploadSignalLocation?
    let payload: JSONValue

    enum CodingKeys: String, CodingKey {
        case id
        case capturedAt = "captured_at"
        case signalType = "signal_type"
        case location
        case payload
    }
}

public struct UploadBatchPayload: Encodable {
    let deviceID: String
    let appVersion: String
    let osVersion: String
    let batchID: String
    let signals: [UploadSignal]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case batchID = "batch_id"
        case signals
    }
}

/// Wraps a pre-encoded JSON payload blob (as stored by `SignalStore`) so it
/// can be embedded verbatim into the batch request without a decode/re-encode
/// round trip.
public struct JSONValue: Encodable {
    let data: Data

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        try container.encode(AnyEncodable(object))
    }
}

private struct AnyEncodable: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as [Any]:
            var arrayContainer = encoder.unkeyedContainer()
            for item in v { try arrayContainer.encode(AnyEncodable(item)) }
        case let v as [String: Any]:
            var keyedContainer = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, item) in v {
                try keyedContainer.encode(AnyEncodable(item), forKey: DynamicCodingKey(stringValue: key)!)
            }
        default:
            try container.encodeNil()
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}

/// Builds an `UploadBatchPayload` from a page of claimed `PendingSignalRow`s.
public enum UploadBatchBuilder {
    public static func build(
        deviceID: UUID,
        appVersion: String,
        osVersion: String,
        batchID: String,
        rows: [(id: String, capturedAt: Date, signalType: String, payloadJSON: Data, lat: Double?, lon: Double?, horizontalAccuracy: Double?, locationAgeSeconds: Double?)]
    ) -> UploadBatchPayload {
        let signals = rows.map { row -> UploadSignal in
            let location: UploadSignalLocation?
            if let lat = row.lat, let lon = row.lon {
                location = UploadSignalLocation(lat: lat, lon: lon, horizontalAccuracyM: row.horizontalAccuracy, ageS: row.locationAgeSeconds)
            } else {
                location = nil
            }
            return UploadSignal(
                id: row.id,
                capturedAt: row.capturedAt,
                signalType: row.signalType,
                location: location,
                payload: JSONValue(data: row.payloadJSON)
            )
        }
        return UploadBatchPayload(
            deviceID: deviceID.uuidString,
            appVersion: appVersion,
            osVersion: osVersion,
            batchID: batchID,
            signals: signals
        )
    }
}
