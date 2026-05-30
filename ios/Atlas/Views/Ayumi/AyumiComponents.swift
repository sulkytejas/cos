import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  Shared Ayumi v0.6 primitives — reused across the six screens.
// ════════════════════════════════════════════════════════════════════

// MARK: - Ayumi prose (italic serif voice with roman + accent runs)

enum ProseStyle { case italic, roman, accent }
struct ProseRun {
    let text: String
    let style: ProseStyle
    init(_ text: String, _ style: ProseStyle = .italic) { self.text = text; self.style = style }
}

/// Ayumi speaks in italic serif; names/numbers stay roman; "accent" words get a
/// teal underline-marker highlight. Composed as one `Text` via AttributedString.
func ayumiProse(_ runs: [ProseRun], size: CGFloat, color: Color = Theme.Palette.ink) -> Text {
    var out = AttributedString()
    for run in runs {
        var a = AttributedString(run.text)
        switch run.style {
        case .italic: a.font = .custom(Theme.Typeface.serifItalic, size: size)
        case .roman:  a.font = .custom(Theme.Typeface.serifRegular, size: size)
        case .accent:
            a.font = .custom(Theme.Typeface.serifRegular, size: size)
            a.backgroundColor = Theme.Palette.teal.opacity(0.16)
        }
        a.foregroundColor = color
        out += a
    }
    return Text(out)
}

// MARK: - ConfidencePill

struct ConfidencePill: View {
    enum Level { case high, med, low }
    let value: Double
    var forced: Level? = nil

    private var level: Level { forced ?? (value >= 0.5 ? .high : .low) }

    var body: some View {
        Text(String(format: "%.2f", value))
            .font(Theme.Font.mono(10))
            .tracking(0.4)
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(bg))
            .overlay(level == .med ? Capsule().stroke(Theme.Palette.rule, lineWidth: 1) : nil)
            .fixedSize()
    }

    private var bg: Color {
        switch level { case .high: Theme.Palette.confHighBg; case .med: Theme.Palette.paperDeep; case .low: Theme.Palette.confLowBg }
    }
    private var fg: Color {
        switch level { case .high: Theme.Palette.confHighInk; case .med: Theme.Palette.ink2; case .low: Theme.Palette.confLowInk }
    }
}

// MARK: - AyumiAvatar (obsidian dot + jade pulse)

struct AyumiAvatar: View {
    var size: CGFloat = 12
    var pulse: Bool = true
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Theme.Palette.obsidian)
            .frame(width: size, height: size)
            .overlay(
                // catchlight
                Circle()
                    .fill(RadialGradient(colors: [Theme.Palette.avatarInk.opacity(0.5), .clear],
                                         center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.5))
            )
            .overlay {
                if pulse {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.Palette.pulseTeal.opacity(0.95), Theme.Palette.jade.opacity(0.0)],
                                             center: .center, startRadius: 0, endRadius: size * 0.5))
                        .frame(width: size * 0.5, height: size * 0.5)
                        .opacity(on ? 1 : 0.4)
                }
            }
            .onAppear {
                guard pulse, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - DayDivider

struct DayDivider: View {
    let label: String
    let roman: String
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1)
            HStack(spacing: 6) {
                Text(label)
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.ink2)
                Text(roman.uppercased())
                    .font(Theme.Font.mono(10))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.ink3)
            }
            .fixedSize()
            Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1)
        }
        .padding(.vertical, 14)
    }
}

// MARK: - EO ring (commit-tap radial pulse)

struct EORingItem: Identifiable, Equatable { let id = UUID(); let point: CGPoint }

/// A self-animating ring; the owner removes it after ~1s.
struct EORingView: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.Palette.pulseTeal.opacity(0.55), .clear],
                                 center: .center, startRadius: 0, endRadius: 190))
            .frame(width: 380, height: 380)
            .scaleEffect(on ? 1 : 12.0 / 380.0)
            .opacity(on ? 0 : 1)
            .onAppear { withAnimation(Theme.Motion.eoRing()) { on = true } }
            .allowsHitTesting(false)
    }
}

/// Overlay layer that renders active rings. Spawn via the binding; pass a
/// removal closure that drops the ring after the animation.
struct EOLayer: View {
    let rings: [EORingItem]
    var body: some View {
        ZStack {
            ForEach(rings) { r in
                EORingView().position(r.point)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Obsidian avatar (initials)

struct AvatarObsidian: View {
    let initials: String
    var size: CGFloat = 50
    var body: some View {
        Circle()
            .fill(Theme.Palette.obsidian)
            .frame(width: size, height: size)
            .overlay(
                Circle().fill(RadialGradient(colors: [Theme.Palette.avatarInk.opacity(0.5), .clear],
                                             center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.5))
            )
            .overlay(
                Text(initials)
                    .font(Theme.Font.serif(size * 0.42))
                    .foregroundStyle(Theme.Palette.avatarInk)
            )
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Jade gradient card (tactical / answer)

struct JadeCard<Content: View>: View {
    var radius: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Palette.jadeCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(RadialGradient(colors: [Color.white.opacity(0.5), .clear],
                                                 center: UnitPoint(x: -0.1, y: -0.3), startRadius: 0, endRadius: 220))
                            .allowsHitTesting(false)
                    )
            )
    }
}

// MARK: - Cite button (opens a receipt)

struct CiteButton: View {
    let label: String
    var tint: Color = Theme.Palette.tealDeep
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().stroke(tint, lineWidth: 1).frame(width: 4, height: 4)
                Text(label).font(Theme.Font.mono(9)).tracking(0.6).foregroundStyle(tint)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pill button

struct PillButton: View {
    enum Kind { case primary, forest, ghost }
    let title: String
    var kind: Kind = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.sans(14, weight: .semibold))
                .foregroundStyle(fg)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(bg))
                .overlay(kind == .ghost ? Capsule().stroke(Theme.Palette.rule, lineWidth: 1) : nil)
        }
        .buttonStyle(.plain)
    }
    private var bg: Color {
        switch kind { case .primary: Theme.Palette.ink; case .forest: Theme.Palette.forest; case .ghost: Theme.Palette.paperDeep }
    }
    private var fg: Color {
        switch kind { case .primary, .forest: .white; case .ghost: Theme.Palette.ink2 }
    }
}
