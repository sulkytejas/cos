import SwiftUI

/// BrushedA — the Ayumi brand mark, rendered from the three SVG paths in the
/// design handoff (Icon options.html). Identical to the bundled app icon but
/// as a vector shape so the header instance scales sharply at any size.
///
/// Three filled paths on a 100×100 viewBox: left leg, right leg, crossbar.
struct BrushedA: View {
    /// Final width (and height) of the mark.
    var size: CGFloat = 24
    /// Ink colour — defaults to Theme.Palette.ink.
    var color: Color = Theme.Palette.ink

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 100.0  // viewBox is 100 units
            ctx.scaleBy(x: s, y: s)
            ctx.fill(BrushedAShape.leftLeg(), with: .color(color))
            ctx.fill(BrushedAShape.rightLeg(), with: .color(color))
            ctx.fill(BrushedAShape.crossbar(), with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

/// Static path data — extracted from Icon options.html (the three SVG
/// paths under hero/header.brush-a-svg). Coordinates are in the 100×100
/// viewBox; scale at render time.
enum BrushedAShape {
    /// Left leg: M 47 8 C 53 7, 60 9, 63 14 ... Z
    static func leftLeg() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 47, y: 8))
        p.addCurve(to: CGPoint(x: 63, y: 14),
                   control1: CGPoint(x: 53, y: 7), control2: CGPoint(x: 60, y: 9))
        p.addCurve(to: CGPoint(x: 28, y: 86),
                   control1: CGPoint(x: 64, y: 22), control2: CGPoint(x: 52, y: 44))
        p.addCurve(to: CGPoint(x: 14, y: 88),
                   control1: CGPoint(x: 24, y: 90), control2: CGPoint(x: 17, y: 92))
        p.addCurve(to: CGPoint(x: 42, y: 34),
                   control1: CGPoint(x: 14, y: 84), control2: CGPoint(x: 22, y: 70))
        p.addCurve(to: CGPoint(x: 47, y: 8),
                   control1: CGPoint(x: 47, y: 24), control2: CGPoint(x: 49, y: 14))
        p.closeSubpath()
        return p
    }
    /// Right leg: M 53 8 C 47 7, 40 9, 37 14 ... Z
    static func rightLeg() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 53, y: 8))
        p.addCurve(to: CGPoint(x: 37, y: 14),
                   control1: CGPoint(x: 47, y: 7), control2: CGPoint(x: 40, y: 9))
        p.addCurve(to: CGPoint(x: 72, y: 86),
                   control1: CGPoint(x: 36, y: 22), control2: CGPoint(x: 48, y: 44))
        p.addCurve(to: CGPoint(x: 86, y: 88),
                   control1: CGPoint(x: 76, y: 90), control2: CGPoint(x: 83, y: 92))
        p.addCurve(to: CGPoint(x: 58, y: 34),
                   control1: CGPoint(x: 86, y: 84), control2: CGPoint(x: 78, y: 70))
        p.addCurve(to: CGPoint(x: 53, y: 8),
                   control1: CGPoint(x: 53, y: 24), control2: CGPoint(x: 51, y: 14))
        p.closeSubpath()
        return p
    }
    /// Crossbar: M 30 56 Q 36 52, 44 55 L 64 57 Q 72 60, 66 66 L 38 66 Q 28 64, 30 56 Z
    static func crossbar() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 30, y: 56))
        p.addQuadCurve(to: CGPoint(x: 44, y: 55), control: CGPoint(x: 36, y: 52))
        p.addLine(to: CGPoint(x: 64, y: 57))
        p.addQuadCurve(to: CGPoint(x: 66, y: 66), control: CGPoint(x: 72, y: 60))
        p.addLine(to: CGPoint(x: 38, y: 66))
        p.addQuadCurve(to: CGPoint(x: 30, y: 56), control: CGPoint(x: 28, y: 64))
        p.closeSubpath()
        return p
    }
}

#Preview {
    VStack(spacing: 24) {
        BrushedA(size: 24)
        BrushedA(size: 80)
        BrushedA(size: 200)
    }
    .padding()
    .background(Theme.Palette.paper)
}
