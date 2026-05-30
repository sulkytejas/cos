import SwiftUI

/// The small radar icon used wherever Atlas is "watching". Two static rings,
/// a centre pip, N/S ticks, plus a rotating sweep arm with a gradient stroke
/// (transparent at centre → teal at tip). 5.4s full revolution.
struct WatcherIcon: View {
    var size: CGFloat = 12
    var color: Color = Theme.Palette.tealDeep
    /// Sweep angle in degrees. When supplied, the icon is driven by a *shared*
    /// parent clock and runs no timeline of its own — so a row of N radars
    /// costs one clock, not N (see PERFORMANCE_REVIEW.md H2). When nil it
    /// self-drives via a gated `AmbientTimeline`.
    var rotation: Double? = nil

    /// Maps wall time → sweep angle. Use to drive several icons from one clock:
    /// `WatcherIcon(rotation: WatcherIcon.angle(now))`.
    static func angle(_ date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return (t.truncatingRemainder(dividingBy: 5.4)) / 5.4 * 360
    }

    var body: some View {
        if let rotation {
            dial(rotation: rotation)
        } else {
            AmbientTimeline(fps: 24) { now in
                dial(rotation: Self.angle(now))
            }
        }
    }

    @ViewBuilder
    private func dial(rotation: Double) -> some View {
        ZStack {
            // Outer ring
            Circle()
                .strokeBorder(color, lineWidth: 0.7)
            // Inner ring
            Circle()
                .strokeBorder(color, lineWidth: 0.7)
                .padding(size * 0.275)
            // Centre pip
            Circle()
                .fill(color)
                .frame(width: size * 0.15, height: size * 0.15)
            // N / S ticks
            Rectangle()
                .fill(color)
                .frame(width: 0.6, height: size * 0.18)
                .offset(y: -size * 0.40)
            Rectangle()
                .fill(color)
                .frame(width: 0.6, height: size * 0.18)
                .offset(y: size * 0.40)
            // Sweep arm — gradient (transparent at centre, opaque at tip)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0), color],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size * 0.42, height: 1.1)
                .offset(x: size * 0.21)
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
    }
}
