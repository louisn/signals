import CoreLocation
import Foundation

/// Wraps `CLLocationManager`. Applies a minimum distance/time filter so a
/// stationary or slow-moving device doesn't flood the queue with near-
/// identical fixes, and caches the latest fix so other capturers can tag
/// their events without requesting a fresh location per event.
public final class LocationCapturer: NSObject, SignalCapturing {
    public weak var delegate: SignalCapturingDelegate?

    public var minimumDistanceMeters: Double = 25
    public var minimumInterval: TimeInterval = 30

    /// Fired whenever the system authorization status changes, including in
    /// response to `requestWhenInUseAuthorization()`/`requestAlwaysAuthorization()`
    /// and to the user changing the grant in Settings.
    public var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    public var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    private let deviceID: UUID
    private let manager = CLLocationManager()
    private var lastEmittedLocation: CLLocation?
    private var lastEmittedAt: Date?

    /// The most recent fix, exposed so other capturers can tag their events
    /// without requesting their own fresh location.
    public private(set) var latestLocation: CLLocation?

    public init(deviceID: UUID) {
        self.deviceID = deviceID
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    public func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    public func stop() {
        manager.stopUpdatingLocation()
    }

    /// Call after the user has separately opted into background collection;
    /// requesting "Always" is a distinct, explicitly-justified ask and
    /// should not happen implicitly from `start()`.
    public func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    #if os(iOS)
    public func enableBackgroundUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }
    #endif

    private func shouldEmit(_ location: CLLocation) -> Bool {
        guard let lastLocation = lastEmittedLocation, let lastAt = lastEmittedAt else {
            return true
        }
        let distance = location.distance(from: lastLocation)
        let elapsed = location.timestamp.timeIntervalSince(lastAt)
        return distance >= minimumDistanceMeters || elapsed >= minimumInterval
    }

    private func makeRecord(from location: CLLocation) -> SignalRecord {
        let tag = LocationTag(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            ageSeconds: 0
        )
        let payload = LocationPayload(
            altitude: location.altitude,
            speed: location.speed >= 0 ? location.speed : nil,
            course: location.course >= 0 ? location.course : nil,
            verticalAccuracy: location.verticalAccuracy
        )
        return SignalRecord(
            deviceID: deviceID,
            capturedAt: location.timestamp,
            location: tag,
            payload: .location(payload)
        )
    }
}

extension LocationCapturer: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        latestLocation = location

        guard shouldEmit(location) else { return }
        lastEmittedLocation = location
        lastEmittedAt = location.timestamp

        delegate?.signalCapturer(self, didCapture: makeRecord(from: location))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (no fix yet, momentary signal loss) are expected
        // and require no action -- CLLocationManager keeps retrying on its own.
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(manager.authorizationStatus)
    }
}
