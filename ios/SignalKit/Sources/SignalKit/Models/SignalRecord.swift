import Foundation

/// The location tag attached to every captured signal, whether or not the
/// signal itself is a location fix. `ageSeconds` lets a consumer judge how
/// stale the tag is when it's a cached fix reused for a BLE/network event.
public struct LocationTag: Equatable {
    public var lat: Double
    public var lon: Double
    public var horizontalAccuracyMeters: Double?
    public var ageSeconds: Double?

    public init(lat: Double, lon: Double, horizontalAccuracyMeters: Double?, ageSeconds: Double?) {
        self.lat = lat
        self.lon = lon
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.ageSeconds = ageSeconds
    }
}

/// A single captured signal, ready to be queued. `id` is generated at
/// capture time (not upload time) so retried uploads stay idempotent.
public struct SignalRecord: Identifiable, Equatable {
    public let id: UUID
    public let deviceID: UUID
    public let capturedAt: Date
    public let location: LocationTag?
    public let payload: SignalPayload

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        capturedAt: Date = Date(),
        location: LocationTag?,
        payload: SignalPayload
    ) {
        self.id = id
        self.deviceID = deviceID
        self.capturedAt = capturedAt
        self.location = location
        self.payload = payload
    }
}
