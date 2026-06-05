import SwiftUI

/// Faint prev/next chevrons just inside the left and right rim, each with a tiny
/// mono label of the destination screen. Tap to move along the page ring.
struct EdgeChevrons: View {
    let prev: AyumiPage
    let next: AyumiPage
    let onPrev: () -> Void
    let onNext: () -> Void
    /// Per-screen overrides for the edge labels when the destination isn't a
    /// plain `AyumiPage` (e.g. Chapters' right edge leads to the North India
    /// Living Chapter, which is an overlay, not a page in the ring).
    var prevLabel: String? = nil
    var nextLabel: String? = nil

    var body: some View {
        HStack {
            chevron(dir: .leading, label: prevLabel ?? prev.title, action: onPrev)
            Spacer()
            chevron(dir: .trailing, label: nextLabel ?? next.title, action: onNext)
        }
        .padding(.horizontal, 8)
    }

    private enum Dir { case leading, trailing }

    private func chevron(dir: Dir, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Chevron(pointsLeading: dir == .leading)
                    .stroke(Theme.Palette.ink4, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 13, height: 13)
                Text(label.uppercased())
                    .font(Theme.Font.mono(7))
                    .tracking(1.3)
                    .foregroundStyle(Theme.Palette.ink4)
                    .fixedSize()
            }
            .opacity(0.42)
            .frame(width: 44, height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A small chevron glyph in a 13×13 box.
private struct Chevron: Shape {
    var pointsLeading: Bool   // true = "<", false = ">"
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        if pointsLeading {
            p.move(to: CGPoint(x: rect.maxX * 0.66, y: rect.minY + rect.height * 0.16))
            p.addLine(to: CGPoint(x: rect.maxX * 0.30, y: midY))
            p.addLine(to: CGPoint(x: rect.maxX * 0.66, y: rect.maxY - rect.height * 0.16))
        } else {
            p.move(to: CGPoint(x: rect.maxX * 0.34, y: rect.minY + rect.height * 0.16))
            p.addLine(to: CGPoint(x: rect.maxX * 0.70, y: midY))
            p.addLine(to: CGPoint(x: rect.maxX * 0.34, y: rect.maxY - rect.height * 0.16))
        }
        return p
    }
}
