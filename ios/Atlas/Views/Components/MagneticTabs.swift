import SwiftUI

/// Top tabs with an ink underline that stretches across both source and target
/// tabs during the switch, then snaps to the target. ("ink pulled across the page")
struct MagneticTabs<ID: Hashable>: View {
    struct Tab: Identifiable {
        let id: ID
        let label: String
    }

    let tabs: [Tab]
    @Binding var active: ID

    @State private var frames: [AnyHashable: CGRect] = [:]
    @State private var displayedFrame: CGRect? = nil

    var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs) { tab in
                Button {
                    switchTo(tab.id)
                } label: {
                    Text(tab.label)
                        .font(active == tab.id
                              ? Theme.Font.serifItalic(18)
                              : Theme.Font.serif(18))
                        .foregroundStyle(active == tab.id ? Theme.Palette.ink : Theme.Palette.inkFaint)
                        .padding(.vertical, 14)
                        .background(
                            GeometryReader { g in
                                Color.clear
                                    .preference(
                                        key: TabFramePref.self,
                                        value: [AnyHashable(tab.id): g.frame(in: .named("magnetic"))]
                                    )
                            }
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .coordinateSpace(name: "magnetic")
        .onPreferenceChange(TabFramePref.self) { dict in
            frames.merge(dict) { _, new in new }
            if displayedFrame == nil, let f = frames[AnyHashable(active)] {
                displayedFrame = f
            }
        }
        .overlay(alignment: .topLeading) {
            if let f = displayedFrame {
                Rectangle()
                    .fill(Theme.Palette.ink)
                    .frame(width: f.width, height: 1.5)
                    .offset(x: f.minX, y: f.maxY - 1.5)
            }
        }
    }

    private func switchTo(_ id: ID) {
        guard id != active,
              let from = frames[AnyHashable(active)],
              let to = frames[AnyHashable(id)] else {
            active = id
            return
        }
        // Phase 1: stretch underline to cover both source + target
        let unionMinX = min(from.minX, to.minX)
        let unionMaxX = max(from.maxX, to.maxX)
        let bridge = CGRect(x: unionMinX, y: from.minY,
                            width: unionMaxX - unionMinX, height: from.height)
        withAnimation(.easeInOut(duration: 0.22)) {
            displayedFrame = bridge
        }
        // Phase 2: snap to target
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                active = id
                displayedFrame = to
            }
        }
    }
}

private struct TabFramePref: PreferenceKey {
    static let defaultValue: [AnyHashable: CGRect] = [:]
    static func reduce(value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
