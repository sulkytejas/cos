import SwiftUI

/// The single sanctioned primitive for looping *decorative* motion in Atlas.
///
/// It wraps `TimelineView(.animation)` but **gates** the per-frame clock so the
/// display-link wakeups stop — and the GPU goes idle — whenever the motion
/// can't be seen or shouldn't run:
///
///   • the scene isn't `.active` (backgrounded / inactive),
///   • the user has **Reduce Motion** enabled,
///   • the device is in **Low Power Mode**, or
///   • the caller marks it off-screen (`active: false`).
///
/// When gated, the timeline simply stops advancing: the content renders once
/// with the last date and holds. This is the difference between Today costing
/// GPU at rest and Today going quiet at rest.
///
/// Prefer this over a raw `TimelineView(.animation(... paused: false))`. The
/// literal `paused: false` is banned by the perf playbook (see
/// PERFORMANCE_REVIEW.md §2) precisely because it can never pause.
///
/// The closure receives the current `Date` (covers every call site here, which
/// only ever read `ctx.date`). Match `fps` to the motion: multi-second drifts
/// want 8–12fps; fast shimmer/translation 24–30. 60 is almost never worth it.
struct AmbientTimeline<Content: View>: View {
    var fps: Double = 30
    /// Caller-supplied visibility/relevance gate (e.g. on-screen + focused).
    var active: Bool = true
    var content: (Date) -> Content

    init(fps: Double = 30, active: Bool = true, @ViewBuilder content: @escaping (Date) -> Content) {
        self.fps = fps
        self.active = active
        self.content = content
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var paused: Bool {
        !active || scenePhase != .active || reduceMotion || lowPower
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: paused)) { ctx in
            content(ctx.date)
        }
        // Low Power Mode isn't an Environment value — observe the system signal.
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
