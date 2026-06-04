import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  CorrectionSheet.swift — quick correction → reconcile (README §A,
//  atlas-trip.css `.correct-*`).
//
//  Opened from a past leg's pencil button, pre-loaded with WHAT AYUMI
//  CURRENTLY BELIEVES (the seeded-wrong "Flew to Pantnagar · ₹4,900").
//  Offers quick-answer chips for the common cases + a free-text well.
//  On submit it hands the chosen answer back so the parent can reconcile
//  (rewrite the leg, animate the spend total, rebalance the legend, and
//  show the ripple toast with the "what I learned" line).
// ════════════════════════════════════════════════════════════════════

struct CorrectionSheet: View {
    let correction: Correction
    /// Returns the chosen answer (a chip label or the free text).
    let onSubmit: (String) -> Void
    let onClose: () -> Void

    @State private var selected: String? = nil
    @State private var freeText: String = ""
    @FocusState private var freeFocused: Bool

    /// The submit answer — free text wins if present, else the chip.
    private var answer: String? {
        let t = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return selected
    }
    private var ready: Bool { answer != nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Backdrop — tap to close.
            Color(hex: 0x0D141A).opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .transition(.opacity)

            card
                .transition(.move(edge: .bottom))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Theme.Palette.ink4.opacity(0.6))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

            // "Ayumi · correction" eyebrow with the breathing avatar.
            HStack(spacing: 7) {
                AyumiAvatar(size: 15)
                Text("AYUMI · CORRECTION")
                    .font(Theme.Font.mono(9))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.ink3)
            }
            .padding(.bottom, 7)

            Text("Set me straight")
                .font(Theme.Font.serif(24))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.bottom, 6)

            // What I assumed — pre-loaded with the current (wrong) belief.
            Text(correction.assumed)
                .font(Theme.Font.serifItalic(15))
                .foregroundStyle(Theme.Palette.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 15)

            // Quick-answer chips.
            FlowChips(options: correction.options, selected: $selected) { id in
                freeText = ""
                freeFocused = false
                selected = (selected == id) ? nil : id
            }
            .padding(.bottom, 14)

            // Free-text well — "…or tell me in your own words."
            ZStack(alignment: .topLeading) {
                if freeText.isEmpty {
                    Text(correction.freeTextPlaceholder)
                        .font(Theme.Font.serifItalic(15))
                        .foregroundStyle(Theme.Palette.ink3)
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
                TextField("", text: $freeText, axis: .vertical)
                    .font(Theme.Font.serifItalic(15))
                    .foregroundStyle(Theme.Palette.ink)
                    .tint(Theme.Palette.teal)
                    .focused($freeFocused)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .onChange(of: freeText) { _, new in
                        if !new.trimmingCharacters(in: .whitespaces).isEmpty { selected = nil }
                    }
            }
            .frame(minHeight: 48, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Palette.paperDeep))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Palette.ruleSoft, lineWidth: 1))
            .padding(.bottom, 14)
            .onTapGesture { freeFocused = true }

            // Submit — dark, disabled until an answer exists (`.cgo.ready`).
            Button { if let a = answer { onSubmit(a) } } label: {
                Text("Got it — fix this")
                    .font(Theme.Font.serif(17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.Palette.ink))
            }
            .buttonStyle(.plain)
            .opacity(ready ? 1 : 0.45)
            .disabled(!ready)
            .animation(Theme.Motion.standard(0.2), value: ready)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 28, style: .continuous)
                .fill(Theme.Palette.paper)
        )
        .shadow(color: Color(hex: 0x141820, opacity: 0.2), radius: 24, x: 0, y: -8)
    }
}

// MARK: - Wrapping chip row (`.cchips` / `.cchip`)

private struct FlowChips: View {
    let options: [Correction.Option]
    @Binding var selected: String?
    let onTap: (String) -> Void

    var body: some View {
        // A simple wrapping layout that stays left-aligned.
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(options) { opt in
                let sel = selected == opt.id
                Button { onTap(opt.id) } label: {
                    Text(opt.label)
                        .font(Theme.Font.sans(13, weight: .medium))
                        .foregroundStyle(sel ? .white : Theme.Palette.ink2)
                        .padding(.horizontal, 15).padding(.vertical, 9)
                        .background(Capsule().fill(sel ? Theme.Palette.ink : Theme.Palette.paperDeep))
                        .overlay(Capsule().strokeBorder(sel ? Theme.Palette.ink : Theme.Palette.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - FlowLayout — minimal wrapping HStack (chips wrap to new lines)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows = layout(subviews, maxWidth: maxWidth)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map { row -> CGFloat in
            row.items.map { $0.size.width }.reduce(0, +) + spacing * CGFloat(max(0, row.items.count - 1))
        }.max() ?? 0
        rows.removeAll()
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = layout(subviews, maxWidth: bounds.width)
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
        }
    }

    private struct Item { let index: Int; let size: CGSize }
    private struct Row { var y: CGFloat; var height: CGFloat; var items: [Item] }

    private func layout(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var current = Row(y: 0, height: 0, items: [])
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !current.items.isEmpty {
                rows.append(current)
                y += current.height + lineSpacing
                current = Row(y: y, height: 0, items: [])
                x = 0
            }
            current.items.append(Item(index: i, size: size))
            x += size.width + spacing
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
