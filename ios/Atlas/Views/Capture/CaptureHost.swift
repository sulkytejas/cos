import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  CaptureHost.swift — the single global capture surface (README §"One
//  surface, reached everywhere"). Overlays the summon cue + the well sheet
//  on top of whatever screen is mounted, bridging that screen's halo so
//  capture drives the same presence animation.
//
//  This is the reusable mount a later integration phase wires above the router
//  outlet (so it captures over the current route and restores the user exactly
//  where they were). It does NOT redraw per screen — it is one instance.
//
//  Owns ONLY composition: the cue (CaptureCue), the sheet (CaptureSheet), and
//  the halo bridge. All behaviour lives in CaptureController + the subviews.
// ════════════════════════════════════════════════════════════════════

struct CaptureHost<Content: View>: View {
    /// The host screen content (the current route).
    @ViewBuilder var content: () -> Content
    /// The screen name shown as "Capturing — over <screen>".
    var screenName: String
    /// The host screen's halo, so capture drives the same presence.
    var halo: HaloController
    /// Lift the cue above a host bottom bar of this height (0 ⇒ normal).
    var avoidBottomInset: CGFloat = 0

    @State private var controller = CaptureController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The repo, so completion/classification + filing run through the server
    /// brain when available (the controller degrades to its seeded dictionary
    /// offline). Optional via the environment default so previews still build.
    @Environment(AtlasRepo.self) private var repo: AtlasRepo?

    /// DEBUG: `--capture-voice` opens the well straight into the voice duet.
    private var debugAutoVoice: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--capture-voice")
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content()

            // The ambient cue — hidden while the well is open (the sheet owns the
            // foot of the screen then).
            if !controller.open {
                CaptureCue(
                    onSummon: { open() },
                    avoidBottomInset: avoidBottomInset
                )
                .transition(.opacity)
            }

            // The well sheet (dim + slide-up). Mounted only while open.
            if controller.open {
                CaptureSheet(controller: controller, onClose: { controller.close() },
                             debugAutoVoice: debugAutoVoice)
                    .zIndex(60)
                    .transition(.identity)
            }
        }
        .onAppear {
            // Bridge the host screen's halo so capture drives the same presence.
            controller.onHaloState = { [weak halo] state in halo?.setState(state) }
            // Attach the repo for real completion/filing (no-op offline).
            if let repo { controller.attach(repo: repo) }
            handleDebugLaunch()
        }
    }

    private func open() {
        withAnimation(Theme.Motion.standard(0.2)) {
            controller.open(over: screenName)
        }
    }

    /// DEBUG: `--capture` auto-opens the well (optionally pre-seeded via
    /// `--capture-seed <fragment-prefix>`) so screenshots land on the well.
    private func handleDebugLaunch() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--capture") else { return }
        let seed: String? = {
            if args.contains("--capture-voice") { return nil }   // voice opens empty
            if let i = args.firstIndex(of: "--capture-seed"), i + 1 < args.count {
                return args[i + 1]
            }
            // A faithful default: the Karan retention fragment co-completes.
            return "Karan wants"
        }()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(Theme.Motion.standard(0.2)) { controller.open(over: screenName) }
            if let seed { await controller.onType(seed) }
        }
        #endif
    }
}
