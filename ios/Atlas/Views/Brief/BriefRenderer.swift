import SwiftUI

/// BriefRenderer — takes a Brief's structureData (JSON-encoded BriefStructure)
/// and instantiates the matching SwiftUI components in order. Unknown section
/// kinds render a FallbackSection so the page never blows up.
struct BriefRenderer: View {
    let brief: Brief

    private var structure: BriefStructure? {
        try? JSONDecoder().decode(BriefStructure.self, from: brief.structureData)
    }

    var body: some View {
        if let structure {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(structure.sections.enumerated()), id: \.offset) { _, section in
                    sectionView(for: section)
                }
            }
        } else {
            FallbackSection(label: "Ayumi couldn't shape this brief — structure is malformed.")
        }
    }

    @ViewBuilder
    private func sectionView(for section: BriefSection) -> some View {
        switch section {
        case .person(let d):     PersonCard(data: d)
        case .timeline(let d):   TimelineSection(data: d)
        case .prediction(let d): PredictionBlock(data: d)
        case .materials(let d):  MaterialsChecklist(data: d)
        case .options(let d):    OptionList(data: d)
        case .tactical(let d):   TacticalNote(data: d)
        case .quote(let d):      QuoteCard(data: d)
        case .watcher(let d):    WatcherCardSection(data: d)
        case .diff(let d):       DiffBlock(data: d)
        case .action(let d):     ActionStripSection(data: d)
        case .unknown(let kind, let data):
            // A kind the renderer doesn't know yet. We still log it to the dev
            // wishlist (so the missing module surfaces) AND paint a generic
            // fallback card in the established section idiom — the page never
            // shows a dead end, and whatever string values Ayumi packed into
            // the section still read through.
            UnknownFallbackCard(kind: kind, data: data)
                .onAppear { logUnknownComponent(kind: kind) }
        }
    }
}

/// Records an unrecognised section kind so it bubbles up to the dev wishlist.
/// (Server-side the worker writes dev_unknown_components; on-device we keep a
/// lightweight breadcrumb in the console for the same reason — to notice which
/// component Ayumi reached for that the library doesn't carry yet.)
private func logUnknownComponent(kind: String) {
    print("[BriefRenderer] unknown component kind: \(kind)")
}

/// Generic fallback for unknown section kinds. Reuses the brief-section card
/// idiom — vertical padding + bottom hairline, a mono uppercased label for the
/// kind, then up to four serif-italic rows pulled from the section data's
/// string values so the content still reads even when we can't shape it.
private struct UnknownFallbackCard: View {
    let kind: String
    let data: [String: String]?

    /// Stable, capped list of the data's string values. Sorted by key so the
    /// order is deterministic across renders rather than dictionary-random.
    private var rows: [String] {
        guard let data, !data.isEmpty else { return [] }
        return data
            .sorted { $0.key < $1.key }
            .map(\.value)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kind name as the section label — same mono/tracked treatment the
            // built sections use (see BriefSectionLabel).
            Text(kind.uppercased())
                .font(Theme.Font.mono(9))
                .tracking(2.2)
                .foregroundStyle(Theme.Palette.inkFaint)
                .padding(.bottom, 10)

            if rows.isEmpty {
                // Nothing structured to show — keep Ayumi's voice, not a blank.
                Text("Ayumi wanted a \(kind) section that isn't built yet.")
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .lineSpacing(3)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Text(row)
                            .font(Theme.Font.serifItalic(14.5))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .lineSpacing(3)
                    }
                }
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.hairlineSoft)
                .frame(height: 1)
        }
    }
}
