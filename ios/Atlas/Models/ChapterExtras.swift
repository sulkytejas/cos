import Foundation
import SwiftUI

// Editorial accent for a chapter — derives from type (Move/Trip/Recurring → forest,
// Project/Launch → teal). Single-letter glyph is the first capital of the title.
enum ChapterAccent {
    case forest
    case teal

    var stroke: Color {
        switch self {
        case .forest: return Theme.Palette.forest
        case .teal:   return Theme.Palette.teal
        }
    }
    var soft: Color {
        switch self {
        case .forest: return Theme.Palette.forestSoft
        case .teal:   return Theme.Palette.tealSoft
        }
    }
}

extension Chapter {
    var accent: ChapterAccent {
        switch type {
        case .project, .launch:                 return .teal
        case .move, .trip, .recurring, .personal: return .forest
        }
    }

    var glyph: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first else { return "·" }
        return String(first).uppercased()
    }

    var rangeShort: String {
        guard let s = startDate else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "M/yy"
        let from = f.string(from: s)
        if let e = endDate {
            if Calendar.current.isDate(s, equalTo: e, toGranularity: .day) {
                return from
            }
            return "\(from) — \(f.string(from: e))"
        }
        return "from \(from)"
    }
}

extension ChapterStatus {
    var prototypeLabel: String {
        switch self {
        case .active:   return "ACTIVE"
        case .upcoming: return "UPCOMING"
        case .paused:   return "PAUSED"
        case .done:     return "COMPLETE"
        }
    }
    var pillBackground: Color {
        switch self {
        case .active:   return Theme.Palette.forestSoft
        case .upcoming: return Theme.Palette.tealSoft
        case .paused:   return Color(red: 0.945, green: 0.929, blue: 0.898)
        case .done:     return Color(red: 0.933, green: 0.941, blue: 0.933)
        }
    }
    var pillForeground: Color {
        switch self {
        case .active:   return Theme.Palette.forest
        case .upcoming: return Theme.Palette.tealDeep
        case .paused, .done: return Theme.Palette.inkFaint
        }
    }
}
