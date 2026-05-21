import SwiftUI

/// The small radar icon used wherever Atlas is "watching". Two static rings,
/// a centre pip, N/S ticks, plus a rotating sweep arm with a gradient stroke
/// (transparent at centre → teal at tip). 5.4s full revolution.
struct WatcherIcon: View {
    var size: CGFloat = 12
    var color: Color = Theme.Palette.tealDeep

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let rotation = (t.truncatingRemainder(dividingBy: 5.4)) / 5.4 * 360
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
}
