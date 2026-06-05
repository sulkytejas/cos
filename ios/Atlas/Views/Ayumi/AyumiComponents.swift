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
            // The mock's `em.accent` is a teal highlighter *band* on the LOWER part
            // of the line, not a full-height box: CSS `background: linear-gradient(
            // 180deg, transparent 65%, rgba(0,137,168,0.18) 65% → 92%, transparent
            // 92%)` — rgba(0,137,168,0.18) (= teal.opacity(0.18)) across only the
            // lower ~27% of the line height (65%→92%), bottom-anchored.
            //
            // SwiftUI's inline AttributedString background can only fill the FULL
            // glyph box — there is no partial-height inline fill, and a pixel-exact
            // bottom-anchored band requires a view-/layout-based renderer with
            // per-word glyph-rect measurement, which would have to replace AyumiTurn's
            // shared `[Text]` paragraph contract across Today/Brief/Review/Search
            // (a large, wrap-correctness-risky migration not safe for this serial
            // shared-file pass — deferred to a dedicated pass). As the faithful,
            // contained stand-in inside the `Text` API, render a full-height wash
            // whose INTEGRATED teal coverage matches the reference band: 0.18 over
            // the lower 27% of the line ≈ 0.049 full-height-equivalent. The prior
            // 0.14 full-height wash laid down ~3× the reference's teal pixels (scan:
            // sim 20872 vs ref 7087); drop it to 0.06 so the accent reads as a pale
            // teal mark of the right total weight rather than a heavy full-height box.
            a.font = .custom(Theme.Typeface.serifRegular, size: size)
            a.backgroundColor = Theme.Palette.teal.opacity(0.06)
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
        // CSS `.turn.ayumi .turn-meta::before` is a 12px dark INK disc
        // (`background: var(--ink)` #0d141a) with a SMALL contained jade glow drawn by
        // `::after`: a 6px circle at `left:1px; top:9px` (the lower-left quadrant, NOT
        // the whole disc), `radial-gradient(circle at 35% 30%, rgba(122,214,198,0.95)
        // [pulseTeal], rgba(90,143,116,0.5) 60% [jade], transparent 100%)`, breathing
        // via `@keyframes gentle { 0%,100%{opacity:.4} 50%{opacity:1} }` over 2.4s.
        //
        // Per-pixel scan of the full-res Today reference dot (x[124–156], y[450–481]
        // @3x): the disc interior is mostly `--ink` (green channel ≈ 20, i.e. #0d141a)
        // with a teal glow whose bright core sits at the disc's lower-CENTER, ≈(0.5,
        // 0.55) normalized, ~size*0.2 across, fading out by ~size*0.4. The prior glow
        // (endRadius size*0.6 centred 0.35/0.30) covered the WHOLE disc, so the dot
        // read as a uniformly dark-jade ball with the ink base lost. Shrink the radial
        // to a small lower-left-of-centre glow over the predominantly near-black ink.
        let glowCenter = UnitPoint(x: 0.42, y: 0.58)   // lower-left-of-centre (CSS ::after at left:1/top:9, clipped)
        let glowEnd = size * 0.40                        // 6px glow on a 12px dot ≈ contained ~0.4·size, not full-disc
        Circle()
            .fill(Theme.Palette.obsidian)               // --ink base #0d141a (obsidian gradient)
            .frame(width: size, height: size)
            .overlay {
                if pulse {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Theme.Palette.pulseTeal.opacity(0.95),
                                     Theme.Palette.jade.opacity(0.5), .clear],
                            center: glowCenter,
                            startRadius: 0, endRadius: glowEnd))
                        .opacity(on ? 1 : 0.4)
                } else {
                    // Non-breathing variant keeps the same contained static glow so
                    // non-pulse call sites still read as a dark ink dot with a small
                    // jade highlight rather than a flat black dot.
                    Circle()
                        .fill(RadialGradient(
                            colors: [Theme.Palette.pulseTeal.opacity(0.95),
                                     Theme.Palette.jade.opacity(0.5), .clear],
                            center: glowCenter,
                            startRadius: 0, endRadius: glowEnd))
                }
            }
            .onAppear {
                guard pulse, !reduceMotion else { return }
                // `@keyframes gentle`: opacity 0.4 ↔ 1 over 2.4s, ease-in-out.
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
                // CSS `.cite` is `font-size:9px; color:var(--teal-deep)` at the mono
                // default weight, but JetBrainsMono at 9pt regular anti-aliases to a
                // washed pale gray-teal in the sim (darkest core ~RGB(105,156,168))
                // vs the reference's crisp #00576b (RGB 0,87,107). The color token is
                // already correct (tealDeep == #00576b) and there is no dimming — the
                // washout is purely the thin 9pt regular strokes. Bump the mono weight
                // to .medium so the heavier strokes reach full teal-deep coverage and
                // match the reference's bolder-looking cite glyphs (ref-strip0).
                Circle().stroke(tint, lineWidth: 1.2).frame(width: 4, height: 4)
                Text(label).font(Theme.Font.mono(9, weight: .medium)).tracking(0.6).foregroundStyle(tint)
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
