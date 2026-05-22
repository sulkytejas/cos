import SwiftUI

/// Real wall-clock that ticks every second.
struct LiveClock: View {
    @State private var now = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatted(now))
            .font(Theme.Font.mono(10.5))
            .foregroundStyle(Theme.Palette.inkFaint)
            .onReceive(timer) { now = $0 }
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

/// Editorial compass dial — hairline outer ring, dashed inner ring, four
/// cardinal ticks (N/E/S/W), a small "N" label at the top, and a lozenge
/// needle (teal half north, ink half south) that slowly drifts and oscillates
/// like a real compass settling toward magnetic north.
struct CompassDial: View {
    var size: CGFloat = 56

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // A real compass needle never sits perfectly still — it slowly
            // hunts around true north. Combine a long-period drift with a
            // shorter wobble to feel alive but unhurried.
            let drift  = sin(t * (2 * .pi / 48)) * 18      // ±18° over 48s
            let wobble = sin(t * (2 * .pi / 4.2)) *  3      // ±3°  over 4.2s
            let needleAngle = drift + wobble

            ZStack {
                // Outer hairline ring
                Circle()
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 0.8)

                // Inner dashed ring
                Circle()
                    .strokeBorder(
                        Theme.Palette.hairline.opacity(0.55),
                        style: StrokeStyle(lineWidth: 0.6, dash: [1.6, 3.6])
                    )
                    .padding(size * 0.18)

                // Cardinal tick marks at N / E / S / W
                ForEach(0..<4, id: \.self) { i in
                    Rectangle()
                        .fill(Theme.Palette.inkFaint.opacity(0.6))
                        .frame(width: 0.8, height: size * 0.07)
                        .offset(y: -size * 0.465)
                        .rotationEffect(.degrees(Double(i) * 90))
                }

                // "N" label at 12 o'clock
                Text("N")
                    .font(Theme.Font.mono(7.5, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .offset(y: -size * 0.34)

                // Compass needle — a tall lozenge.
                // The two halves use opposite colours so it reads as a needle
                // even though we only draw a single shape.
                ZStack {
                    // North half (teal) — points up
                    Triangle()
                        .fill(Theme.Palette.teal)
                        .frame(width: size * 0.10, height: size * 0.36)
                        .offset(y: -size * 0.09)
                    // South half (ink) — points down, slightly thinner so the
                    // north end visually dominates (compass convention)
                    Triangle()
                        .fill(Theme.Palette.ink)
                        .frame(width: size * 0.08, height: size * 0.30)
                        .rotationEffect(.degrees(180))
                        .offset(y: size * 0.07)
                    // Pivot dot
                    Circle()
                        .fill(Theme.Palette.ink)
                        .frame(width: 2.4, height: 2.4)
                }
                .rotationEffect(.degrees(needleAngle))
            }
            .frame(width: size, height: size)
        }
    }
}

/// Thin isoceles triangle pointing up — used for the compass needle halves.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
