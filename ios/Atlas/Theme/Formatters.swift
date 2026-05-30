import Foundation
import SwiftUI

enum AtlasFormat {
    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    /// Wall-clock HH:mm:ss — used by the always-visible header clock once a
    /// second, so it must be a cached static (never built per tick).
    static let clockHMS: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Cached relative formatter — the one `AtlasFormat` helper that was still
    /// allocating per call (inside row bodies). DateFormatters are reusable on
    /// the main thread.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func range(_ start: Date?, _ end: Date?) -> String {
        guard start != nil || end != nil else { return "ongoing" }
        if let s = start, let e = end {
            let sy = Calendar.current.component(.year, from: s)
            let ey = Calendar.current.component(.year, from: e)
            if sy == ey {
                return "\(shortDay.string(from: s)) – \(mediumDate.string(from: e))"
            }
            return "\(mediumDate.string(from: s)) – \(mediumDate.string(from: e))"
        }
        if let s = start { return "from \(mediumDate.string(from: s))" }
        if let e = end { return "until \(mediumDate.string(from: e))" }
        return ""
    }

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func daysUntil(_ date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: target).day ?? 0
    }
}

/// Time-of-day band — used to shift editorial labels across the day so the
/// Morning page reads "This afternoon" / "This evening" / "Tonight" as the
/// clock turns. Bands are tuned to feel natural in everyday speech.
enum TimeBand {
    case morning, afternoon, evening, night

    /// Optional override — when non-nil, returned by `current` instead of
    /// reading the clock. Used for previews / dev testing.
    static var debugOverride: TimeBand? = nil

    /// Reads the system clock and picks the band.
    /// Thresholds match the v0.3 Night-icon handoff (5–12 / 12–17 / 17–20 /
    /// 20–5) — "a calm professional's day".
    static var current: TimeBand {
        if let o = debugOverride { return o }
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<20: return .evening
        default:      return .night     // 20, 21, 22, 23, 0, 1, 2, 3, 4
        }
    }

    /// Bottom-nav tab label.
    var tabLabel: String {
        switch self {
        case .morning:   return "Morning"
        case .afternoon: return "Afternoon"
        case .evening:   return "Evening"
        case .night:     return "Night"
        }
    }

    /// Italic-serif headline shown on the page ("This morning", "Tonight"…).
    var pageTitle: String {
        switch self {
        case .morning:   return "This morning"
        case .afternoon: return "This afternoon"
        case .evening:   return "This evening"
        case .night:     return "Tonight"
        }
    }

    /// Mono eyebrow on the Today entry-point. The phrasing changes so it
    /// always reads as a backward glance over what Ayumi processed.
    var todayEyebrow: String {
        switch self {
        case .morning:   return "I SAT WITH LAST NIGHT"
        case .afternoon: return "I SAT WITH YOUR MORNING"
        case .evening:   return "I SAT WITH YOUR DAY"
        case .night:     return "I SAT WITH YOUR DAY"
        }
    }

    /// Italic line in the "filed" confirmation panel.
    var filedNoun: String {
        switch self {
        case .morning:   return "morning"
        case .afternoon: return "afternoon"
        case .evening:   return "evening"
        case .night:     return "night"
        }
    }

    /// Current lunar phase as a fraction 0..1.
    /// 0 = new · 0.25 = first quarter · 0.5 = full · 0.75 = last quarter.
    /// The same all over Earth — the moon shows everyone the same illuminated
    /// fraction at the same UTC moment (modulo a few hours of libration).
    /// Reference epoch is 2000-01-06 18:14 UTC, a known new moon.
    static func moonPhase(at date: Date = Date()) -> Double {
        let knownNewMoon = Date(timeIntervalSince1970: 947182440)   // 2000-01-06 18:14 UTC
        let synodicMonth: Double = 29.530588853                      // days
        let daysSince = date.timeIntervalSince(knownNewMoon) / 86400.0
        let cycles = daysSince / synodicMonth
        let fractional = cycles - floor(cycles)
        return fractional < 0 ? fractional + 1 : fractional
    }
}

extension Color {
    static func dueColor(for date: Date?) -> Color {
        guard let date else { return Theme.Palette.inkFaint }
        let d = AtlasFormat.daysUntil(date)
        if d < 0 { return Theme.Palette.ember }
        if d <= 3 { return Theme.Palette.ember }
        if d <= 14 { return Theme.Palette.inkSecondary }
        return Theme.Palette.inkFaint
    }
}
