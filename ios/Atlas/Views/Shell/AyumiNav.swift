import SwiftUI
import Observation

/// The six surfaces, as a wrapping ring: Today → Brief → Capture → Chapters →
/// Review → Search → (Today). There is no tab bar — movement is via the
/// logo-menu index sheet, edge chevrons, and horizontal swipe.
enum AyumiPage: Int, CaseIterable, Identifiable, Hashable {
    case today, brief, capture, chapters, review, search
    var id: Int { rawValue }

    /// App-mark crumb + index-sheet name.
    var title: String {
        switch self {
        case .today: "Today"
        case .brief: "Brief"
        case .capture: "Capture"
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
        case .capture: "what did you notice"
        case .chapters: "5 threads"
        case .review: "4 overnight"
        case .search: "everything"
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
