import SwiftUI

/// Editorial section header — serif title left, mono uppercase meta right,
/// 28pt top / 12pt bottom breath. Used between cards.
struct RibbonHeader: View {
    let title: String
    var meta: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(Theme.Font.serif(22))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
            if let meta {
                Spacer()
                MicroText(text: meta)
            } else {
                Spacer()
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 12)
    }
}

/// Chapter monogram — either the generated line-art icon (when present) or
/// the italic-serif letter fallback. Both sit inside the same hairline square
/// so chapters look consistent whether the AI icon has arrived yet or not.
struct ChapterGlyphView: View {
    let letter: String
    var iconData: Data? = nil
    var accent: ChapterAccent = .forest
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.Palette.card)
                )
                .frame(width: size, height: size)

            if let data = iconData, let img = IconCropping.cropped(data) {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    // Cropped icon — fill ~90% of the box so it visually
                    // matches the italic letter's optical weight.
                    .frame(width: size * 0.90, height: size * 0.90)
                    .transition(.opacity)
            } else {
                Text(letter)
                    .font(Theme.Font.serifItalic(size * 0.62))
                    .foregroundStyle(accent.stroke)
                    .baselineOffset(-1)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.32), value: iconData)
    }
}

/// Subtle state pill (ACTIVE / UPCOMING / PAUSED / COMPLETE).
struct StatePill: View {
    let status: ChapterStatus
    var body: some View {
        Text(status.prototypeLabel)
            .font(Theme.Font.mono(9.5, weight: .regular))
            .tracking(1.6)
            .foregroundStyle(status.pillForeground)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(status.pillBackground)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

/// Hairline progress bar (2px). The filled portion animates over 600ms.
struct HairlineProgress: View {
    let done: Int
    let total: Int
    var accent: ChapterAccent = .forest

    var body: some View {
        GeometryReader { geo in
            let pct = total > 0 ? Double(done) / Double(total) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.hairline).frame(height: 2)
                Capsule()
                    .fill(accent.stroke)
                    .frame(width: max(0, geo.size.width * pct), height: 2)
                    .animation(.easeOut(duration: 0.6), value: pct)
            }
        }
        .frame(height: 2)
    }
}

/// Inline chapter tag — hairline ring + chapter title, for compact rows.
struct ChapterChip: View {
    let title: String
    var accent: ChapterAccent = .forest
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .strokeBorder(accent.stroke, lineWidth: 1)
                .frame(width: 9, height: 9)
            Text(title)
                .font(Theme.Font.sans(11.5, weight: .medium))
                .foregroundStyle(accent.stroke)
                .lineLimit(1)
        }
    }
}
