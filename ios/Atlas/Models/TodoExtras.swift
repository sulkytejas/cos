import Foundation

extension Todo {
    /// Hour-of-day (0–24, fractional) used by the HourRibbon. Nil → no time set.
    var dueHourDouble: Double? {
        guard let due = dueDate else { return nil }
        let cal = Calendar.current
        // Only surface as hour-of-day if the due date is today.
        guard cal.isDateInToday(due) else { return nil }
        let comps = cal.dateComponents([.hour, .minute], from: due)
        let h = Double(comps.hour ?? 0)
        let m = Double(comps.minute ?? 0) / 60.0
        return h + m
    }

    var isOverdue: Bool {
        guard let due = dueDate, !done else { return false }
        return due < Date()
    }
}
