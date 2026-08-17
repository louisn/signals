import Foundation
#if os(iOS)
import BackgroundTasks

/// Registers a `BGProcessingTask` for opportunistic sync when the app is
/// backgrounded. The OS schedules actual execution at its own discretion --
/// this is a best-effort hook, not a guaranteed-timing mechanism. Must be
/// registered during app launch (before `application(_:didFinishLaunchingWithOptions:)`
/// returns) per `BGTaskScheduler` requirements, and the identifier must
/// match an entry in the app's `Info.plist` `BGTaskSchedulerPermittedIdentifiers`.
public final class BackgroundTaskCoordinator {
    public static let taskIdentifier = "com.signals.sync"

    private let syncEngine: SyncEngine

    public init(syncEngine: SyncEngine) {
        self.syncEngine = syncEngine
    }

    public func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            self?.handle(task as! BGProcessingTask)
        }
    }

    public func scheduleNextRun() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Scheduling can fail (e.g. too many pending requests); the next
            // foreground/connectivity-restored trigger will still cover sync.
        }
    }

    private func handle(_ task: BGProcessingTask) {
        scheduleNextRun()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        syncEngine.triggerSync()
        // SyncEngine's loop is synchronous within its own serial queue, so by
        // the time control returns here the best-effort pass has completed.
        task.setTaskCompleted(success: true)
    }
}
#endif
