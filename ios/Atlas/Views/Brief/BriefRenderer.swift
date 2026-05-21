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
            FallbackSection(label: "Atlas couldn't shape this brief — structure is malformed.")
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
        case .unknown(let kind, _):
            FallbackSection(label: "Atlas wanted a \(kind) section that isn't built yet.")
        }
    }
}
