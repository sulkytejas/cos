import SwiftUI

/// The Halo as a full-bleed background layer. Drives `HaloController` at a fixed
/// ~32ms cadence and GATES the timeline so it stops entirely at rest (no
/// redraws, GPU idle) — unlike the JS reference, which spins `setInterval`
/// forever. Mount this behind a page surface inset ~22pt so only the rim shows.
///
/// Timeline choice: `.animation(minimumInterval: 0.032, paused:)` — NOT
/// `.periodic`. `.periodic` can't be paused, and at-rest gating is required by
/// this app's perf playbook (PERFORMANCE_REVIEW.md). `.animation(minimumInterval:)`
/// throttles to ~32ms (one `advance()` per fire, ~30fps on both 60/120Hz) and
/// supports `paused:`. Do NOT change it to `.animation` with no interval — that
/// fires per display frame and the per-tick tuning constants would feel 2–4× fast.
struct HaloView: View {
    var controller: HaloController

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var paused: Bool {
        _ = controller.restGeneration    // observe the rest token so this recomputes when the engine settles
        return controller.isAtRest || scenePhase != .active || lowPower
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.032, paused: paused)) { _ in
            Canvas { ctx, size in
                // Advance the fixed-timestep sim, then draw — one step per Canvas
                // redraw (TimelineView re-renders the content each tick). The sim
                // mutates only @ObservationIgnored fields here; the rare observed
                // flips (settle / rest-wake) are deferred off the draw by the
                // controller. (`.onChange(of: timeline.date)` proved unreliable.)
                controller.advance(size: size, reduceMotion: reduceMotion)
                controller.render(into: &ctx, size: size)
            }
        }
        .blur(radius: 1.6)               // the signature softness (CSS filter: blur(1.6px))
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
