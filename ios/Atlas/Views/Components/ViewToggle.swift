import SwiftUI

/// Tiny mono segmented toggle (Map / List). Pill slides between selections.
struct AtlasViewToggle<ID: Hashable>: View {
    struct Option: Identifiable {
        let id: ID
        let label: String
    }

    let options: [Option]
    @Binding var selection: ID

    @State private var sizes: [ID: CGSize] = [:]
    @State private var offsets: [ID: CGFloat] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { _, opt in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        selection = opt.id
                    }
                } label: {
                    Text(opt.label.uppercased())
                        .font(Theme.Font.mono(9.5))
                        .tracking(1.4)
                        .foregroundStyle(selection == opt.id ? Color.white : Theme.Palette.inkFaint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            GeometryReader { g in
                                Color.clear
                                    .onAppear {
                                        sizes[opt.id] = g.size
                                        offsets[opt.id] = g.frame(in: .named("toggle")).minX
                                    }
                                    .onChange(of: g.size) { _, s in sizes[opt.id] = s }
                                    .onChange(of: g.frame(in: .named("toggle")).minX) { _, x in offsets[opt.id] = x }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        // Single background layer — bgSunk paints first, the sliding ink pill
        // paints on top of it, then the labels draw above both. Combining them
        // into one .background prevents the pill from disappearing behind the
        // surface (the bug we had with two separate .background modifiers).
        .background {
            ZStack(alignment: .leading) {
                Theme.Palette.bgSunk
                if let s = sizes[selection], let x = offsets[selection] {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Palette.ink)
                        .frame(width: s.width, height: s.height)
                        .offset(x: x - 2)
                        .padding(2)
                        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: selection)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.Palette.hairline.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .coordinateSpace(name: "toggle")
    }
}
