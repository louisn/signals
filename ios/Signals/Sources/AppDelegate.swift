import UIKit
import SignalKit

/// `BGTaskScheduler.register(forTaskWithIdentifier:...)` must run before
/// `application(_:didFinishLaunchingWithOptions:)` returns (Apple's
/// documented requirement) -- an `@StateObject` created during `App.init()`
/// doesn't reliably guarantee that ordering, so `CaptureController` (which
/// registers the background task in its own `init`) is created here instead.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let capture: CaptureController

    override init() {
        Self.resetStateIfNeeded()
        capture = CaptureController()
        super.init()
    }

    /// UI tests pass `-uitesting-reset` so each run starts from a known
    /// state (onboarding not yet acknowledged, no device key) regardless of
    /// what a previous run left in the simulator's persisted app state.
    private static func resetStateIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-uitesting-reset") else { return }
        UserDefaults.standard.removeObject(forKey: "hasAcknowledgedConsent")
        UserDefaults.standard.removeObject(forKey: "hasSkippedProvisioning")
        UserDefaults.standard.removeObject(forKey: "hasSkippedBackgroundUpgrade")
        APIKeyStore.clear()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        true
    }
}
