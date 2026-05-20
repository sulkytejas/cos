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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func daysUntil(_ date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: target).day ?? 0
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
