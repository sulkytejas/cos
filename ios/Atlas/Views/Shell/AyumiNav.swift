import SwiftUI
import Observation

/// The five surfaces, as a wrapping ring: Today → Brief → Chapters → Review →
/// Search → (Today). There is no tab bar — movement is via the logo-menu index
/// sheet, edge chevrons, and horizontal swipe. Capture is NOT a destination
/// (v0.7): it is Ayumi, summoned in place via the global cue on every screen.
enum AyumiPage: Int, CaseIterable, Identifiable, Hashable {
    case today, brief, chapters, review, search
    var id: Int { rawValue }

    /// App-mark crumb + index-sheet name.
    var title: String {
        switch self {
        case .today: "Today"
        case .brief: "Brief"
        case .chapters: "Chapters"
        case .review: "Review"
        case .search: "Search"
        }
    }

    /// One-line subtitle in the index sheet (data-driven later).
    var subtitle: String {
        switch self {
        case .today: "the thread"
        case .brief: "Karan · 14:30"
        case .chapters: "5 threads"
        case .review: "4 overnight"
        case .search: "everything"
        }
    }

    /// Height of any host bottom action/compose bar the global capture cue must
    /// lift above (README §"Avoid bottom bars"). 0 ⇒ the cue sits at the foot
    /// with its paper gradient. Brief carries a sticky "Start the meeting" bar.
    var captureAvoidInset: CGFloat {
        switch self {
        case .brief: 64    // the sticky actionZone
        default: 0
        }
    }

    var next: AyumiPage { AyumiPage(rawValue: (rawValue + 1) % AyumiPage.allCases.count)! }
    var prev: AyumiPage { AyumiPage(rawValue: (rawValue + AyumiPage.allCases.count - 1) % AyumiPage.allCases.count)! }
}

/// Owns the current ring position. Injected via `.environment`.
@MainActor
@Observable
final class NavRouter {
    var current: AyumiPage = .today
    /// Direction of the last move (+1 next / −1 prev) — drives the slide transition.
    var direction: Int = 1

    func go(_ p: AyumiPage) {
        guard p != current else { return }
        direction = p.rawValue >= current.rawValue ? 1 : -1
        current = p
    }
    func goNext() { direction = 1; current = current.next }
    func goPrev() { direction = -1; current = current.prev }
}
