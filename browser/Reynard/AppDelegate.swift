import UIKit
import BackgroundTasks

class AppDelegate: UIResponder, UIApplicationDelegate {

    /// BGProcessingTask identifier — must match Info.plist BGTaskSchedulerPermittedIdentifiers.
    static let bgTaskID = "com.minh-ton.ReynardLite.refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Apply jetsam priority to the main process right at launch.
        // Gecko child processes are handled in GeckoRuntime.childProcessDidStart.
        updateJetsamPriority(getpid())
        updateJetsamControl(getpid())

        // Start the JIT enablement pipeline.
        JITController.shared.start()

        // Register the background processing task. iOS requires this before
        // application(_:didFinishLaunchingWithOptions:) returns.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppDelegate.bgTaskID,
            using: nil
        ) { task in
            Self.handleBackgroundRefresh(task as! BGProcessingTask)
        }

        return true
    }

    // MARK: - Background refresh

    private static func handleBackgroundRefresh(_ task: BGProcessingTask) {
        // Re-schedule immediately so there is always a future wakeup queued.
        scheduleBackgroundRefresh()

        // The task runs when the OS decides to grant background time
        // (usually while charging + idle). We just need to keep the
        // BGTaskScheduler chain alive; the audio session keeps Gecko warm.
        task.setTaskCompleted(success: true)
    }

    /// Queue the next BGProcessingTask wakeup. Call this every time the app
    /// backgrounds so iOS knows we want background execution opportunities.
    static func scheduleBackgroundRefresh() {
        let request = BGProcessingTaskRequest(identifier: bgTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // Don't specify earliestBeginDate — let iOS schedule it immediately.
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Scene lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {}
}
