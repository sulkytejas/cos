import SwiftUI

/// The Atlas mark — a confident peak rising above a thin horizon line.
/// Reads as a mountain silhouette, a north arrow, or an abstract "look up"
/// gesture. Pure black ink on pure white, edge-to-edge — iOS applies the
/// rounded mask when used as an app icon.
struct AtlasLogo: View {
    /// Final size on screen. The mark scales proportionally.
    var size: CGFloat = 1024
    /// If `true`, the mark renders with a slow gentle breathing scale —
    /// useful in-app for a living header glyph. Set `false` when exporting
    /// to PNG.
    var breathing: Bool = false

    private let ink = Color(red: 0.051, green: 0.078, blue: 0.102)   // #0d141a

    var body: some View {
        ZStack {
            Color.white                                              // edge-to-edge surface
            Group {
                if breathing {
                    markView.breathing()
                } else {
                    markView
                }
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var markView: some View {
        Canvas { ctx, sz in
            let s = sz.width
            // Peak — apex slightly above optical centre, base shoulders
            // sitting just above the horizon line.
            let apex      = CGPoint(x: s * 0.50, y: s * 0.24)
            let shoulderL = CGPoint(x: s * 0.20, y: s * 0.71)
            let shoulderR = CGPoint(x: s * 0.80, y: s * 0.71)

            var peak = Path()
            peak.move(to: shoulderL)
            peak.addLine(to: apex)
            peak.addLine(to: shoulderR)
            ctx.stroke(
                peak,
                with: .color(ink),
                style: StrokeStyle(
                    lineWidth: s * 0.075,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            // Horizon — thin hairline a bit below the shoulders.
            var horizon = Path()
            horizon.move(to: CGPoint(x: s * 0.12, y: s * 0.80))
            horizon.addLine(to: CGPoint(x: s * 0.88, y: s * 0.80))
            ctx.stroke(
                horizon,
                with: .color(ink),
                style: StrokeStyle(
                    lineWidth: s * 0.018,
                    lineCap: .round
                )
            )
        }
    }
}

#Preview {
    AtlasLogo(size: 256)
}
