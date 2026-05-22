import Foundation
import BackgroundTasks
import SwiftData
import os

/// BackgroundRefresh — registers a BGAppRefreshTask so iOS can wake the app
/// every ~30 minutes (best effort; iOS decides based on usage). On wake, we
/// run one AtlasAgent.tickOnce, then immediately reschedule.
///
/// Info.plist must include the identifier under BGTaskSchedulerPermittedIdentifiers
/// and "fetch" in UIBackgroundModes for this to work on a real device.
enum BackgroundRefresh {
    static let identifier = "com.atlas.app.refresh"
    static let log = Logger(subsystem: "com.atlas.app", category: "BackgroundRefresh")

    /// Call from AtlasApp.init — must run before app finishes launching.
    static func register() {
        let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            handle(task: refresh)
        }
        log.info("BG task register: \(ok ? "OK" : "FAILED", privacy: .public)")
    }

    /// Schedule the next refresh. Idempotent — call after each tick.
    static func schedule(after seconds: TimeInterval = 30 * 60) {
        let req = BGAppRefreshTaskRequest(identifier: identifier)
        req.earliestBeginDate = Date().addingTimeInterval(seconds)
        do {
            try BGTaskScheduler.shared.submit(req)
            log.info("scheduled next refresh in \(Int(seconds))s")
        } catch {
            log.error("schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(task: BGAppRefreshTask) {
        log.info("BG refresh fired")
        // Always reschedule first — if we crash mid-tick, we still get another shot.
        schedule()

        let runTask = Task {
            await AtlasAgent.shared.tickOnce()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            log.error("BG refresh expired by iOS — cancelling")
            runTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
