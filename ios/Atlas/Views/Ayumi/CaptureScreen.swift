import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  CaptureScreen.swift — RETIRED (v0.7).
//
//  Capture is no longer a destination. It is Ayumi, summoned in place over
//  whatever screen you're on, via the global cue (CaptureCue) + well sheet
//  (CaptureSheet) mounted ONCE in PageShell. The standalone Capture screen
//  and its nav entry were removed (the `.capture` case is gone from
//  AyumiPage; the index sheet and swipe ring no longer list it).
//
//  This view is kept only as a safe redirect: if anything still routes here
//  it bounces to Today. See README §PART 1 ("No Capture destination").
// ════════════════════════════════════════════════════════════════════

struct CaptureScreen: View {
    @Environment(NavRouter.self) private var router

    var body: some View {
        // Nothing to draw — Capture isn't a place anymore. Return to Today.
        Color.clear
            .onAppear {
                withAnimation(Theme.Motion.overshoot()) { router.go(.today) }
            }
    }
}
