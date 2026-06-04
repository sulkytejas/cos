import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  Shared primitives for the Living Chapter (v0.7, North India).
//
//  Faithful ports of the small reusable pieces in atlas-trip.css that
//  several sections need: the provenance "how she knows it" chip, the
//  section scaffold (mono label + a "how I know" cite pill), the recs
//  cards, the live-tracking cards, the receipts thread, and the dark
//  "ripple" toast a correction emits.
//
//  Every value here is taken verbatim from atlas-trip.css / README §PART 2.
//  Tokens come from Theme + AyumiTokens (teal/forest/jade/sand/ink scale).
// ════════════════════════════════════════════════════════════════════

// MARK: - Provenance chip — `.know.booked/.inferred/.live/.told`

/// "How she knows it" — the provenance chip on every fact (README: always show
/// provenance). booked = solid green, inferred = dashed teal, live = teal,
/// told = dark "you told me" (highest authority, set after a correction).
struct ProvenanceChip: View {
    let provenance: Provenance

    var body: some View {
        Text(provenance.label.uppercased())
            .font(Theme.Font.mono(8))
            .tracking(0.8)
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(bg)
                    .overlay(provenance == .inferred
                        ? Capsule().strokeBorder(Theme.Palette.tealDeep.opacity(0.45),
                                                 style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                        : nil)
            )
            .fixedSize()
    }

    private var bg: Color {
        switch provenance {
        case .booked:   return Theme.Palette.confHighBg          // #d9e7d8
        case .inferred: return .clear
        case .live:     return Theme.Palette.tealSoft            // #e0f1f4
        case .told:     return Color(hex: 0x14181C)             // dark "you told me"
        }
    }
    private var fg: Color {
        switch provenance {
        case .booked:   return Theme.Palette.confHighInk         // #16321e
        case .inferred: return Theme.Palette.tealDeep
        case .live:     return Theme.Palette.tealDeep
        case .told:     return Theme.Palette.avatarInk          // #fffceb
        }
    }
}

// MARK: - Section scaffold — `.sec .label` + optional `.src-pill`

/// A chapter section: the mono uppercase label (with the teal cite pill on the
/// right that opens a receipt sheet), then the section body.
struct ChapterSection<Content: View>: View {
    let title: String
    /// Optional "how I know" / cite pill label; tapping it fires `onCite`.
    var cite: String? = nil
    var onCite: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(Theme.Font.mono(9))
                    .tracking(2.0)
                    .foregroundStyle(Theme.Palette.ink3)
                Spacer(minLength: 8)
                if let cite, let onCite {
                    Button(action: onCite) {
                        HStack(spacing: 5) {
                            Circle().strokeBorder(Theme.Palette.tealDeep, lineWidth: 1)
                                .frame(width: 4, height: 4)
                            Text(cite)
                                .font(Theme.Font.mono(8))
                                .tracking(0.8)
                                .foregroundStyle(Theme.Palette.tealDeep)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)

            content()
        }
        .padding(.top, 24)
    }
}

// MARK: - Recommendation card — `.rec`

struct RecCard: View {
    let rec: Recommendation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail — gradient swatch (r1 forest / r2 teal / r3 sand) + a
            // top-left highlight.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(thumbGradient)
                .frame(width: 46, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.4), .clear],
                                             center: UnitPoint(x: 0.30, y: 0.26),
                                             startRadius: 0, endRadius: 32))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.Palette.ruleSoft, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(rec.text)
                    .font(Theme.Font.serif(16))
                    .foregroundStyle(Theme.Palette.ink)
                Text(rec.place.uppercased())
                    .font(Theme.Font.mono(8.5))
                    .tracking(0.7)
                    .foregroundStyle(Theme.Palette.ink3)
                    .padding(.top, 3)
                // The taste-signal justification — italic serif; the view
                // leaves it whole (the design emphasises a teal phrase inside,
                // which we approximate with the deep-teal body for the signal).
                Text(rec.tasteSignal)
                    .font(Theme.Font.serifItalic(13))
                    .foregroundStyle(Theme.Palette.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.Palette.card)
        )
        .shadow1()
    }

    private var thumbGradient: LinearGradient {
        switch rec.thumb {
        case "r1": return LinearGradient(colors: [Color(hex: 0x1F5D4A), Color(hex: 0x0D3324)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
        case "r2": return LinearGradient(colors: [Color(hex: 0x2A86A3), Color(hex: 0x00576B)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
        default:   return LinearGradient(colors: [Color(hex: 0xD6A45A), Color(hex: 0xA76A23)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Live-tracking card — `.tcard`

struct TrackingCard: View {
    let stat: TrackingStat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if stat.kind == .plain {
                    // wide "trip so far" card — no live dot
                } else {
                    LiveDot()
                }
                Text(stat.label.uppercased())
                    .font(Theme.Font.mono(8.5))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Palette.ink3)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(stat.value)
                    .font(Theme.Font.serif(30))
                    .foregroundStyle(Theme.Palette.ink)
                if let unit = stat.unit {
                    Text(unit)
                        .font(Theme.Font.serif(14))
                        .foregroundStyle(Theme.Palette.ink3)
                }
            }
            .padding(.top, 9)

            // The visual flourish — dots / sparkline / nothing.
            switch stat.kind {
            case .dots: progressDots
            case .bars: sparkline
            case .plain: EmptyView()
            }

            Text(stat.sub)
                .font(Theme.Font.mono(9))
                .tracking(0.3)
                .foregroundStyle(Theme.Palette.ink3)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.Palette.card))
        .shadow1()
    }

    // places visited — `.dots`
    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(Array(stat.dots.enumerated()), id: \.offset) { _, d in
                Capsule()
                    .fill(dotFill(d))
                    .frame(height: 6)
                    .overlay(d == .off
                        ? Capsule().strokeBorder(Theme.Palette.ruleSoft, lineWidth: 1) : nil)
            }
        }
        .padding(.top, 11)
    }
    private func dotFill(_ d: TrackingStat.DotState) -> Color {
        switch d {
        case .off:  return Theme.Palette.paperDeep
        case .on:   return Theme.Palette.ink
        case .here: return Theme.Palette.teal
        }
    }

    // today's steps — `.bars`
    private var sparkline: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(stat.bars.enumerated()), id: \.offset) { _, b in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(b.dim ? Theme.Palette.ink4 : Theme.Palette.teal)
                    .opacity(b.dim ? 0.5 : 0.85)
                    .frame(height: max(3, 42 * b.height))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 42, alignment: .bottom)
        .padding(.top, 11)
    }
}

/// The small breathing teal "live" dot used on tracking cards (`.tcard .tk .d`).
struct LiveDot: View {
    var size: CGFloat = 5
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle()
            .fill(Theme.Palette.teal)
            .frame(width: size, height: size)
            .opacity(on ? 1 : 0.4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - "How I built this" thread — `.build` / `.bi`

struct BuildThread: View {
    let steps: [BuildStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 0) {
                    // The node dot — solid (fact) or hollow (inference).
                    VStack(spacing: 0) {
                        Circle()
                            .fill(step.inferred ? Color.clear : Theme.Palette.ink)
                            .overlay(Circle().strokeBorder(Theme.Palette.ink, lineWidth: step.inferred ? 1 : 0))
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)
                    }
                    .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.src.uppercased())
                            .font(Theme.Font.mono(9))
                            .tracking(0.5)
                            .foregroundStyle(Theme.Palette.tealDeep)
                        buildBody(step.text)
                            .font(Theme.Font.serif(14.5))
                            .foregroundStyle(Theme.Palette.ink2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 13)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.leading, 4)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.Palette.rule).frame(width: 1)
        }
    }

    /// Render the `**bold**` accent runs from the seed as roman ink inside the
    /// italic serif body (`.bi .txt b` — roman, full ink).
    private func buildBody(_ raw: String) -> Text {
        var out = Text("")
        let parts = raw.components(separatedBy: "**")
        for (i, part) in parts.enumerated() where !part.isEmpty {
            if i % 2 == 1 {
                out = out + Text(part).font(Theme.Font.serif(14.5)).foregroundColor(Theme.Palette.ink)
            } else {
                out = out + Text(part).font(Theme.Font.serifItalic(14.5))
            }
        }
        return out
    }
}

// MARK: - Ripple toast — `.ripple-toast`

/// The dark forest "ripple" toast a correction emits: what changed (with a jade
/// accent) + the "what I learned" line. Slides up; auto-dismisses.
struct RippleToast: View {
    let ripple: Ripple

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECONCILED")
                .font(Theme.Font.mono(8.5))
                .tracking(1.4)
                .foregroundStyle(Color(hex: 0xEAF3EE).opacity(0.6))
            // "what changed" — the jade accent is the spend-delta phrase.
            rippleMain
                .font(Theme.Font.serifItalic(16))
                .foregroundStyle(Color(hex: 0xEAF3EE))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(ripple.learned)
                .font(Theme.Font.serifItalic(13))
                .foregroundStyle(Color(hex: 0xEAF3EE).opacity(0.78))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.Palette.confHighInk)              // #16321e forest
        )
        .shadow(color: Theme.Palette.forest.opacity(0.5), radius: 22, x: 0, y: 12)
    }

    /// Emphasise the "Spend …" delta clause in jade.
    private var rippleMain: Text {
        guard let range = ripple.changed.range(of: "Spend", options: .caseInsensitive) else {
            return Text(ripple.changed)
        }
        let head = String(ripple.changed[..<range.lowerBound])
        let tail = String(ripple.changed[range.lowerBound...])
        return Text(head).font(Theme.Font.serifItalic(16))
            + Text(tail).font(Theme.Font.serif(16)).foregroundColor(Color(hex: 0x9FE0C4))
    }
}
