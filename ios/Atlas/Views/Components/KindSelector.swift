import SwiftUI

/// Capture sheet kind picker (Todo / Decision / Journal). Pill slides; selected
/// label flips to italic serif white.
enum CaptureKind: String, CaseIterable, Identifiable {
    case todo, decision, journal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todo: return "Todo"
        case .decision: return "Decision"
        case .journal: return "Journal"
        }
    }
}

struct KindSelector: View {
    @Binding var value: CaptureKind

    @State private var sizes: [CaptureKind: CGSize] = [:]
    @State private var offsets: [CaptureKind: CGFloat] = [:]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CaptureKind.allCases) { kind in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        value = kind
                    }
                } label: {
                    Text(kind.label)
                        .font(value == kind ? Theme.Font.serifItalic(16) : Theme.Font.serif(16))
                        .foregroundStyle(value == kind ? Color.white : Theme.Palette.inkSecondary)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(
                            GeometryReader { g in
                                Color.clear
                                    .onAppear {
                                        sizes[kind] = g.size
                                        offsets[kind] = g.frame(in: .named("kind")).minX
                                    }
                                    .onChange(of: g.size) { _, s in sizes[kind] = s }
                                    .onChange(of: g.frame(in: .named("kind")).minX) { _, x in offsets[kind] = x }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            ZStack(alignment: .leading) {
                Theme.Palette.bgSunk
                if let s = sizes[value], let x = offsets[value] {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Palette.ink)
                        .frame(width: s.width, height: s.height)
                        .offset(x: x - 3)
                        .padding(3)
                        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: value)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.Palette.hairline.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .coordinateSpace(name: "kind")
    }
}

/// Three-way mono segmented control (Calm / Terse / Warm) for Settings.
enum BriefTone: String, CaseIterable, Identifiable {
    case calm, terse, warm
    var id: String { rawValue }
}

struct ToneSegmented: View {
    @Binding var value: BriefTone
    @State private var sizes: [BriefTone: CGSize] = [:]
    @State private var offsets: [BriefTone: CGFloat] = [:]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BriefTone.allCases) { tone in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { value = tone }
                } label: {
                    Text(tone.rawValue.uppercased())
                        .font(Theme.Font.mono(10.5))
                        .tracking(1.3)
                        .foregroundStyle(value == tone ? Theme.Palette.ink : Theme.Palette.inkFaint)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            GeometryReader { g in
                                Color.clear
                                    .onAppear {
                                        sizes[tone] = g.size
                                        offsets[tone] = g.frame(in: .named("tone")).minX
                                    }
                                    .onChange(of: g.size) { _, s in sizes[tone] = s }
                                    .onChange(of: g.frame(in: .named("tone")).minX) { _, x in offsets[tone] = x }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            ZStack(alignment: .leading) {
                Theme.Palette.bgSunk
                if let s = sizes[value], let x = offsets[value] {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Palette.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                        )
                        .frame(width: s.width, height: s.height)
                        .offset(x: x - 3)
                        .padding(3)
                        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: value)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.Palette.hairline.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .coordinateSpace(name: "tone")
    }
}
