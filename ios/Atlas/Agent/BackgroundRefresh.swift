import Foundation

/// BackgroundRefresh — NEUTRALIZED (SERVER_ARCHITECTURE.md §4.e).
///
/// This registered a `BGAppRefreshTask` that woke the app to run the on-device
/// `AtlasAgent.tickOnce()`. The brain now runs 24/7 on the SERVER worker
/// (systemd, `Restart=always`), so the device no longer needs a background task
/// to advance the queue — overnight scans happen server-side and the client
/// pulls the results via `repo.sync()` on foreground.
///
/// The `BGTaskScheduler` registration, the `com.atlas.app.refresh` identifier
/// (also removed from Info.plist), and the `fetch`/`processing` background modes
/// have all been DELETED. This stub remains only to document the removal; it has
/// no callers.
enum BackgroundRefresh {
    /// No-op — there is no on-device background task to register.
    static func register() {}
    /// No-op — there is no on-device background task to schedule.
    static func schedule(after seconds: TimeInterval = 0) {}
}
