import SwiftUI

struct HourEvent: Identifiable, Equatable {
    let id = UUID()
    let time: String      // "HH:MM"
    let title: String
    let meta: String
    let glyph: String
    let durationMin: Int

    var startHour: Double {
        let parts = time.split(separator: ":")
        let h = Double(parts.first ?? "0") ?? 0
        let m = parts.count > 1 ? Double(parts[1]) ?? 0 : 0
        return h + m / 60.0
    }
    var endHour: Double { startHour + Double(durationMin) / 60.0 }
}
