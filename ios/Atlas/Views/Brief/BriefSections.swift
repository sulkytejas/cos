import SwiftUI

/// The 10 brief sections, native SwiftUI. Visual vocabulary mirrors the web
/// side (serif for emphasis, mono for metadata, hairline borders, restrained
/// palette). Each takes a typed `data` from BriefStructure.swift.

// ─────────────────────── 1. PersonCard ───────────────────────

struct PersonCard: View {
    let data: PersonData
    var body: some View {
        BriefSectionContainer {
            BriefSectionLabel("Person")
            HStack(alignment: .top, spacing: 14) {
                Avatar(text: data.avatar)
                VStack(alignment: .leading, spacing: 3) {
                    Text(data.name)
                        .font(Theme.Font.serif(21))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(data.role)
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Palette.inkFaint)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(data.facts, id: \.self) { fact in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(Theme.Palette.inkFaint)
                            .frame(width: 3, height: 3)
                            .offset(y: -3)
                        Text(fact)
                            .font(Theme.Font.sans(13.5))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .lineSpacing(3)
                    }
                }
            }
            .padding(.top, 4)
            if let mutual = data.mutual, !mutual.isEmpty {
                Divider().padding(.top, 12)
                BriefSectionLabel("Mutual", size: 9)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(mutual) { m in
                        HStack {
                            Text(m.name)
                                .font(Theme.Font.serif(14))
                                .foregroundStyle(Theme.Palette.ink)
                            Spacer()
                            Text(m.via)
                                .font(Theme.Font.mono(10))
                                .foregroundStyle(Theme.Palette.inkFaint)
                        }
                    }
                }
            }
        }
    }
}

private struct Avatar: View {
    let text: String
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Palette.bgSunk)
            Text(text)
                .font(Theme.Font.serifItalic(18))
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .frame(width: 44, height: 44)
    }
}

// ─────────────────────── 2. TimelineSection ───────────────────────

struct TimelineSection: View {
    let data: TimelineData
    var body: some View {
        BriefSectionContainer {
            BriefSectionLabel(data.title)
            HStack(alignment: .top, spacing: 0) {
                // Rail
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Theme.Palette.hairline)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 9)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(data.items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .stroke(Theme.Palette.inkFaint, lineWidth: 1)
                                .background(Circle().fill(item.subtle == true ? .clear : Theme.Palette.card))
                                .frame(width: 9, height: 9)
                                .offset(x: -13, y: 4)
                                .frame(width: 0, height: 0, alignment: .topLeading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.date)
                                    .font(Theme.Font.mono(10))
                                    .foregroundStyle(Theme.Palette.inkFaint)
                                Text(item.text)
                                    .font(Theme.Font.sans(13.5))
                                    .foregroundStyle(Theme.Palette.inkSecondary)
                                    .lineSpacing(3)
                            }
                        }
                        .opacity(item.subtle == true ? 0.55 : 1)
                    }
                }
            }
        }
    }
}

// ─────────────────────── 3. PredictionBlock ───────────────────────

struct PredictionBlock: View {
    let data: PredictionData
    var body: some View {
        BriefSectionContainer {
            BriefSectionLabel(data.title)
            VStack(spacing: 0) {
                ForEach(Array(data.items.enumerated()), id: \.element.id) { idx, item in
                    HStack(alignment: .top, spacing: 12) {
                        ConfidenceGauge(level: gaugeLevel(item.confidence))
                            .padding(.top, 4)
                        Text(item.text)
                            .font(Theme.Font.sans(13.5))
                            .foregroundStyle(Theme.Palette.ink)
                            .lineSpacing(3)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    if idx < data.items.count - 1 {
                        Rectangle()
                            .fill(Theme.Palette.hairlineSoft)
                            .frame(height: 1)
                    }
                }
            }
        }
    }
    private func gaugeLevel(_ c: PredictionData.Item.Confidence) -> Int {
        switch c { case .high: return 3; case .medium: return 2; case .low: return 1 }
    }
}

private struct ConfidenceGauge: View {
    let level: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(1...3, id: \.self) { n in
                Rectangle()
                    .fill(n <= level ? Theme.Palette.teal : Theme.Palette.hairline)
                    .frame(width: 2.5, height: CGFloat(4 + (n - 1) * 3))
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
    }
}

// ─────────────────────── 4. MaterialsChecklist ───────────────────────

struct MaterialsChecklist: View {
    let data: MaterialsData
    @State private var ready: [String: Bool] = [:]
    var body: some View {
        BriefSectionContainer {
            BriefSectionLabel(data.title)
            VStack(spacing: 0) {
                ForEach(Array(data.items.enumerated()), id: \.element.id) { idx, item in
                    let isReady = ready[item.id] ?? item.ready
                    HStack(spacing: 10) {
                        InkCheckbox(
                            checked: isReady,
                            accent: .forest,
                            onToggle: { ready[item.id] = !isReady }
                        )
                        Text(item.text)
                            .font(.system(size: 13.5,
                                          weight: isReady ? .light : .regular,
                                          design: .default))
                            .foregroundStyle(isReady ? Theme.Palette.inkFaint : Theme.Palette.ink)
                            .strikethrough(isReady, color: Theme.Palette.inkFainter)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .onTapGesture { ready[item.id] = !isReady }
                    if idx < data.items.count - 1 {
                        Rectangle()
                            .fill(Theme.Palette.hairlineSoft)
                            .frame(height: 1)
                    }
                }
            }
        }
    }
}

// ─────────────────────── 5. OptionList ───────────────────────

struct OptionList: View {
    let data: OptionsData
    var body: some View {
        BriefSectionContainer {
            BriefSectionLabel(data.title)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(data.items) { item in
                    let recommended = item.mark == "recommended"
                    HStack(alignment: .top, spacing: 0) {
                        Rectangle()
                            .fill(recommended ? Theme.Palette.teal : Theme.Palette.hairline)
                            .frame(width: 2)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.label)
                                    .font(recommended
                                          ? Theme.Font.serifItalic(16)
                                          : Theme.Font.serif(16))
                                    .foregroundStyle(Theme.Palette.ink)
                                if recommended {
                                    Text("· SUGGESTED")
                                        .font(Theme.Font.mono(9))
                                        .tracking(1.6)
                                        .foregroundStyle(Theme.Palette.tealDeep)
                                }
                            }
                            Text(item.reasoning)
                                .font(Theme.Font.sans(13))
                                .foregroundStyle(Theme.Palette.inkSecondary)
                                .lineSpacing(3)
                        }
                        .padding(.leading, 14)
                    }
                }
            }
        }
    }
}

// ─────────────────────── 6. TacticalNote ───────────────────────

struct TacticalNote: View {
    let data: TacticalData
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Theme.Palette.forest)
                .frame(width: 2)
                .padding(.vertical, 14)
            VStack(alignment: .leading, spacing: 8) {
                Text("TACTICAL")
                    .font(Theme.Font.mono(9))
                    .tracking(2.0)
                    .foregroundStyle(Theme.Palette.forest)
                Text(data.text)
                    .font(Theme.Font.serifItalic(16))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(4)
            }
            .padding(.leading, 14)
            .padding(.vertical, 16)
            .padding(.trailing, 18)
        }
        .materialB(tint: .forest)
        .padding(.vertical, 12)
    }
}

// ─────────────────────── 7. QuoteCard ───────────────────────

struct QuoteCard: View {
    let data: QuoteData
    var body: some View {
        BriefSectionContainer {
            BriefSectionLabel("Quoted")
            ZStack(alignment: .topLeading) {
                Text("\u{201C}")
                    .font(Theme.Font.serif(52))
                    .italic()
                    .foregroundStyle(Theme.Palette.teal.opacity(0.45))
                    .offset(x: -2, y: -8)
                VStack(alignment: .leading, spacing: 10) {
                    Text(data.text)
                        .font(Theme.Font.serif(17))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineSpacing(4)
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Theme.Palette.inkFaint)
                            .frame(width: 14, height: 1)
                        Text(data.attribution)
                            .font(Theme.Font.mono(10))
                            .tracking(0.4)
                            .foregroundStyle(Theme.Palette.inkFaint)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }
}

// ─────────────────────── 8. ActionStrip ───────────────────────

struct ActionStripSection: View {
    let data: ActionData
    var onPrimary: () -> Void = {}
    var onSecondary: (Int) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrimary) {
                HStack(spacing: 8) {
                    Text(data.primary)
                        .font(Theme.Font.sans(13.5, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.Palette.ink)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            ForEach(Array(data.secondary.enumerated()), id: \.offset) { idx, label in
                Button { onSecondary(idx) } label: {
                    Text(label)
                        .font(Theme.Font.sans(12, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// ─────────────────────── 9. WatcherCard ───────────────────────

struct WatcherCardSection: View {
    let data: WatcherSectionData
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.bgSunk)
                WatcherIcon(size: 14)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text("AYUMI IS WATCHING")
                    .font(Theme.Font.mono(9))
                    .tracking(2.0)
                    .foregroundStyle(Theme.Palette.tealDeep)
                Text(data.text)
                    .font(Theme.Font.serifItalic(16))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(4)
                Text("re-checks \(data.cadence)\(data.last.map { " · last \($0)" } ?? "")")
                    .font(Theme.Font.mono(9.5))
                    .foregroundStyle(Theme.Palette.inkFainter)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        // Brief section rendered in a scroll → single-shadow elevation. (H4)
        .cardElevation()
        .padding(.vertical, 12)
    }
}

// ─────────────────────── 10. DiffBlock ───────────────────────

struct DiffBlock: View {
    let data: DiffData
    var body: some View {
        BriefSectionContainer {
            BriefSectionLabel(data.title)
            VStack(spacing: 0) {
                ForEach(Array(data.items.enumerated()), id: \.element.id) { idx, item in
                    HStack(alignment: .top, spacing: 12) {
                        Text(symbol(item.kind))
                            .font(Theme.Font.mono(13, weight: .medium))
                            .foregroundStyle(color(item.kind))
                            .frame(width: 12, alignment: .leading)
                        Text(item.text)
                            .font(Theme.Font.sans(13.5))
                            .foregroundStyle(item.kind == .removed ? Theme.Palette.inkFaint : Theme.Palette.ink)
                            .strikethrough(item.kind == .removed, color: Theme.Palette.inkFainter)
                            .lineSpacing(3)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    if idx < data.items.count - 1 {
                        Rectangle()
                            .fill(Theme.Palette.hairlineSoft)
                            .frame(height: 1)
                    }
                }
            }
        }
    }
    private func symbol(_ k: DiffData.Item.Kind) -> String {
        switch k { case .added: return "+"; case .removed: return "−"; case .changed: return "↺" }
    }
    private func color(_ k: DiffData.Item.Kind) -> Color {
        switch k {
        case .added:   return Theme.Palette.forest
        case .removed: return Theme.Palette.inkFaint
        case .changed: return Theme.Palette.tealDeep
        }
    }
}

// ─────────────────────── shared containers ───────────────────────

private struct BriefSectionLabel: View {
    let text: String
    var size: CGFloat = 9
    init(_ text: String, size: CGFloat = 9) {
        self.text = text
        self.size = size
    }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.mono(size))
            .tracking(2.2)
            .foregroundStyle(Theme.Palette.inkFaint)
            .padding(.bottom, 10)
    }
}

/// Standard padding + bottom hairline used by most brief sections.
private struct BriefSectionContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.hairlineSoft)
                .frame(height: 1)
        }
    }
}

// ─────────────────────── FallbackSection ───────────────────────

struct FallbackSection: View {
    let label: String
    var body: some View {
        Text(label)
            .font(Theme.Font.serifItalic(14))
            .foregroundStyle(Theme.Palette.inkFaint)
            .padding(.vertical, 18)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.Palette.hairlineSoft)
                    .frame(height: 1)
            }
    }
}
