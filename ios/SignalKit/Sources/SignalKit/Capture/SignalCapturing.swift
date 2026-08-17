import Foundation

public protocol SignalCapturingDelegate: AnyObject {
    func signalCapturer(_ capturer: SignalCapturing, didCapture record: SignalRecord)
}

/// Common interface for every capture source (location, BLE, network
/// metadata). Each capturer owns its own platform framework session and
/// emits fully-tagged `SignalRecord`s to its delegate rather than returning
/// them synchronously, since capture is inherently event-driven.
public protocol SignalCapturing: AnyObject {
    var delegate: SignalCapturingDelegate? { get set }
    func start()
    func stop()
}
