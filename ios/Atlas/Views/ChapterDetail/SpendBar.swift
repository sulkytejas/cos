import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  SpendBar.swift — the "spent so far" panel (README §3, atlas-trip.css
//  `.spend-*`): a big ₹ number of a projected total, a stacked segment
//  bar (flights/stays/food/travel — sand for food), a legend with
//  amounts, and the source note.
//
//  A correction animates the total (`.big.flash` → jade) and rebalances
//  the legend; both are driven off `spend`, which the parent mutates.
// ════════════════════════════════════════════════════════════════════

struct SpendSection: View {
    /// The live spend (the parent mutates this on a correction → it animates).
    let spend: Spend
    /// True while the reconcile flash is active (`.big.flash`).
    let flashing: Bool
    /// Opens the spend receipt (the "sources" cite).
    var onCite: (() -> Void)? = nil

    var body: some View {
        ChapterSection(title: "Spent so far", cite: "where from", onCite: onCite) {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                segmentBar.padding(.top, 12)
                legend.padding(.top, 12)
                sourceNote.padding(.top, 13)
            }
        }
    }

    // ── Big number of projected ──────────────────────────────────────
    private var topRow: some View {
        HStack(alignment: .bottom) {
            // ₹34,750 — the currency glyph is smaller + faint (`.big .cur`).
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(Spend.currency)
                    .font(Theme.Font.serif(20))
                    .foregroundStyle(Theme.Palette.ink3)
                Text(grouped(spend.total))
                    .font(Theme.Font.serif(34))
                    .foregroundStyle(flashing ? Theme.Palette.jade : Theme.Palette.ink)
                    .contentTransition(.numericText(value: Double(spend.total)))
            }
            .animation(Theme.Motion.standard(0.3), value: flashing)
            .animation(.easeInOut(duration: 0.6), value: spend.total)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 1) {
                Text("of ~\(Spend.currency)\(grouped(spend.projected))")
                    .font(Theme.Font.mono(9.5))
                    .foregroundStyle(Theme.Palette.ink)
                Text("projected")
                    .font(Theme.Font.mono(9.5))
                    .foregroundStyle(Theme.Palette.ink3)
            }
        }
    }

    // ── Stacked segment bar ──────────────────────────────────────────
    //
    // Segments scale against the PROJECTED total (not the spent sum) so the
    // filled portion reads as spent-vs-budget and the `--paper-deep` track shows
    // through on the right as the remaining headroom — matching `.spend-bar` in
    // atlas-trip.css (fixed segment widths that sum to < 100%).
    private var segmentBar: some View {
        GeometryReader { geo in
            // The denominator is the projected total, floored at the spent sum so
            // an over-budget trip still fills the bar (never overflows).
            let spent = spend.segments.flights + spend.segments.stays
                + spend.segments.food + spend.segments.travel
            let denom = max(1, max(spend.projected, spent))
            let w = geo.size.width
            HStack(spacing: 0) {
                seg(spend.segments.flights, denom, w, Theme.Palette.forest)   // .s-flight
                seg(spend.segments.stays,   denom, w, Theme.Palette.teal)     // .s-stay
                seg(spend.segments.food,    denom, w, Color(hex: 0xC98A3A))   // .s-food (sand)
                seg(spend.segments.travel,  denom, w, Theme.Palette.ink4)     // .s-misc
                Spacer(minLength: 0)                                          // headroom track
            }
        }
        .frame(height: 8)
        .background(Capsule().fill(Theme.Palette.paperDeep))
        .overlay(Capsule().strokeBorder(Theme.Palette.ruleSoft, lineWidth: 1))
        .clipShape(Capsule())
    }
    private func seg(_ amt: Int, _ denom: Int, _ w: CGFloat, _ color: Color) -> some View {
        color.frame(width: max(0, w * CGFloat(amt) / CGFloat(denom)))
            .animation(.easeInOut(duration: 0.6), value: amt)
    }

    // ── Legend (rebalances on a correction) ──────────────────────────
    private var legend: some View {
        let rows: [(String, Color, Int)] = [
            ("Flights", Theme.Palette.forest, spend.segments.flights),
            ("Stays",   Theme.Palette.teal,   spend.segments.stays),
            ("Food",    Color(hex: 0xC98A3A), spend.segments.food),
            ("Travel",  Theme.Palette.ink4,   spend.segments.travel),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                                   GridItem(.flexible(), spacing: 16)],
                         alignment: .leading, spacing: 9) {
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(row.1).frame(width: 8, height: 8)
                    Text(row.0)
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(Theme.Palette.ink2)
                    Spacer(minLength: 4)
                    Text("\(Spend.currency)\(grouped(row.2))")
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(Theme.Palette.ink3)
                        .contentTransition(.numericText(value: Double(row.2)))
                        .animation(.easeInOut(duration: 0.6), value: row.2)
                }
            }
        }
    }

    // ── Source note (where each number came from + what's NOT counted) ─
    private var sourceNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(spend.sources.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Theme.Font.serifItalic(13.5))
                    .foregroundStyle(Theme.Palette.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────
    private func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.groupingSize = 3
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
