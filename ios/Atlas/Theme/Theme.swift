import SwiftUI
import UIKit

enum Theme {
    enum Palette {
        // Surfaces
        static let paper = Color("ColorPaper")          // pure white
        static let card = Color("ColorCard")            // pure white
        static let bgSunk = Color("ColorBgSunk")        // #fafaf8

        // Hairlines
        static let hairline = Color("ColorBorderWarm")           // ink @ 0.10
        static let hairlineStrong = Color("ColorBorderWarmStrong") // ink @ 0.20
        static let hairlineSoft = Color(red: 20/255, green: 30/255, blue: 36/255).opacity(0.06) // v0.3 row/section rule
        // Legacy aliases
        static var borderWarm: Color { hairline }
        static var borderWarmStrong: Color { hairlineStrong }

        // Ink scale
        static let ink = Color("ColorInk")                 // #0d141a (ink)
        static let inkSecondary = Color("ColorInkSecondary") // #2c3942 (ink-2)
        static let inkFaint = Color("ColorInkFaint")       // #6a7480 (ink-3)
        static let inkFainter = Color("ColorInkFainter")   // #aab2bb (ink-4)

        // Forest (secondary)
        static let forest = Color("ColorMoss")             // #0d3324
        static let forestSoft = Color("ColorMossSoft")     // #e3ebe7

        // Teal (primary)
        static let teal = Color("ColorEmber")              // #0089a8
        static let tealDeep = Color("ColorTealDeep")       // #00576b
        static let tealSoft = Color("ColorEmberSoft")      // #e0f1f4

        // Legacy aliases so older references still resolve
        static var moss: Color { forest }
        static var mossSoft: Color { forestSoft }
        static var ember: Color { teal }
        static var emberSoft: Color { tealSoft }
    }

    enum Typeface {
        // Bundled fonts (registered in Info.plist's UIAppFonts).
        // Match the prototype's css: Instrument Serif + Manrope + JetBrains Mono.
        // Shippori Mincho is added for the splash kanji (歩) and for any
        // Japanese-flavored brand moments — falls back to the iOS-built-in
        // Hiragino Mincho ProN if not registered.
        static let serifRegular = "InstrumentSerif-Regular"
        static let serifItalic  = "InstrumentSerif-Italic"
        static let sansFamily   = "Manrope"                 // weighted via Manrope-Medium etc.
        static let monoFamily   = "JetBrainsMono"           // ditto
        static let kanjiSerif   = "ShipporiMincho-Bold"     // bundled
        static let kanjiFallback = "HiraMinProN-W6"         // iOS system fallback
    }

    enum Font {
        // Instrument Serif — non-italic
        static func serif(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom(Typeface.serifRegular, size: size).weight(weight)
        }
        // Instrument Serif — italic
        static func serifItalic(_ size: CGFloat) -> SwiftUI.Font {
            .custom(Typeface.serifItalic, size: size)
        }
        // Manrope — picks the right weight instance from the variable font
        static func sans(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom(manropeName(for: weight), size: size)
        }
        // JetBrains Mono — picks the right weight instance from the variable font
        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom(jetBrainsMonoName(for: weight), size: size)
        }
        /// Shippori Mincho — used for the kanji 歩 on the splash and any
        /// Japanese-flavored brand moments. Falls back to Hiragino Mincho ProN
        /// W6 (bundled with iOS) when the file isn't available.
        static func kanji(_ size: CGFloat) -> SwiftUI.Font {
            if UIFont(name: Typeface.kanjiSerif, size: size) != nil {
                return .custom(Typeface.kanjiSerif, size: size)
            }
            return .custom(Typeface.kanjiFallback, size: size)
        }

        private static func manropeName(for weight: SwiftUI.Font.Weight) -> String {
            switch weight {
            case .light, .ultraLight, .thin: return "Manrope-Light"
            case .medium:                    return "Manrope-Medium"
            case .semibold:                  return "Manrope-SemiBold"
            case .bold, .heavy, .black:      return "Manrope-Bold"
            default:                         return "Manrope-Regular"
            }
        }

        private static func jetBrainsMonoName(for weight: SwiftUI.Font.Weight) -> String {
            // The variable font registers "JetBrainsMono-Regular" for the base
            // weight but all other weights show up as "JetBrainsMonoRoman-X".
            switch weight {
            case .ultraLight, .thin:    return "JetBrainsMonoRoman-Thin"
            case .light:                return "JetBrainsMonoRoman-Light"
            case .medium, .semibold:    return "JetBrainsMonoRoman-Medium"
            case .bold, .heavy, .black: return "JetBrainsMonoRoman-Bold"
            default:                    return "JetBrainsMono-Regular"
            }
        }

        // Editorial roles
        static let display = serifItalic(72)        // Today date
        static let pageTitle = serif(46)            // "Chapters", "Settings"
        static let chapterTitle = serifItalic(36)   // chapter masthead
        static let heading = serif(22)              // ribbon section titles
        static let body = sans(15)
        static let bodyMuted = sans(14)
        static let label = sans(13)
        static let metaUpper = mono(10, weight: .medium)
        static let metaSmall = mono(11)

        // Legacy aliases
        static let title = serif(34)
        static let titleLarge = serif(46)
    }

    enum Radii {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
    }
}

// ─── Hairline divider ────────────────────────────────────────────────
struct Hairline: View {
    var horizontal: Bool = true
    var color: Color = Theme.Palette.hairline
    var body: some View {
        color.frame(maxWidth: horizontal ? .infinity : 1,
                    maxHeight: horizontal ? 1 : .infinity)
            .frame(height: horizontal ? 1 : nil)
    }
}

// ─── v0.3 Material system ────────────────────────────────────────────
// Three substances under one light source (top-left, ~30°). Containers no
// longer carry hairline borders — separation comes from material + shadow.
// Defined once here and applied via `.materialA/.materialB/.materialC` (and
// `.card()`, which is Material A), so there is a single source of truth for
// every elevated surface.

/// Ink used for shadows + soft rules (#141e24 — the v0.3 `--hairline` base).
private let inkRule = Color(red: 20/255, green: 30/255, blue: 36/255)

/// Vellum tint options for Material B.
enum MaterialTint { case none, teal, forest }

/// The raking-light shadow stack (one light source, top-left). Single source of
/// truth for every material's cast; `pressed` tightens it for the press state.
private struct RakingShadow: ViewModifier {
    var pressed: Bool = false
    func body(content: Content) -> some View {
        content
            .shadow(color: inkRule.opacity(0.04), radius: 0.5, x: 0, y: 0.5)
            .shadow(color: inkRule.opacity(pressed ? 0.05 : 0.07),
                    radius: pressed ? 3 : 5, x: 1, y: pressed ? 1.5 : 3)
            .shadow(color: inkRule.opacity(pressed ? 0.08 : 0.12),
                    radius: pressed ? 6 : 11, x: 3, y: pressed ? 4 : 8)
    }
}

/// The 1px top highlight that catches the raking light.
private struct TopHighlight: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        )
    }
}

/// The raking-light "lift" — directional shadow + top highlight, *no background*.
/// For surfaces that supply their own fill (e.g. TempoNow's animated aura) so
/// they match Material A's elevation without a second background layer.
struct MaterialLift: ViewModifier {
    var radius: CGFloat = Theme.Radii.lg
    var pressed: Bool = false
    func body(content: Content) -> some View {
        content.modifier(RakingShadow(pressed: pressed)).modifier(TopHighlight(radius: radius))
    }
}

/// Material A — paper under raking light. The default elevated surface: white
/// fill, no border, the raking-light lift. `pressed` tightens the cast.
struct MaterialA: ViewModifier {
    var radius: CGFloat = Theme.Radii.lg
    var pressed: Bool = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.Palette.card))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(MaterialLift(radius: radius, pressed: pressed))
    }
}

/// Material B — vellum. A translucent supporting surface that lets the page
/// tone bleed through; optional teal/forest tint. No outer shadow.
struct MaterialB: ViewModifier {
    var tint: MaterialTint = .none
    var radius: CGFloat = Theme.Radii.md
    private var tintColor: Color {
        switch tint {
        case .none:   return .clear
        case .teal:   return Theme.Palette.teal
        case .forest: return Theme.Palette.forest
        }
    }
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(red: 0.988, green: 0.988, blue: 0.980).opacity(0.5)))
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tintColor.opacity(0.05)))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 0.5)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
    }
}

/// Material C — pressed specimen. Lifted higher than A with a longer, slightly
/// asymmetric cast. Used sparingly: only the agentic "noticed" ask.
struct MaterialC: ViewModifier {
    var radius: CGFloat = Theme.Radii.lg
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: inkRule.opacity(0.05), radius: 0.5, x: 0, y: 1)
            .shadow(color: inkRule.opacity(0.08), radius: 7, x: 3, y: 6)
            .shadow(color: inkRule.opacity(0.15), radius: 14, x: 6, y: 16)
            .shadow(color: inkRule.opacity(0.10), radius: 22, x: 10, y: 28)
    }
}

extension View {
    /// Material A — default elevated surface. Pass `pressed:` for the press state.
    func materialA(radius: CGFloat = Theme.Radii.lg, pressed: Bool = false) -> some View {
        modifier(MaterialA(radius: radius, pressed: pressed))
    }
    /// Raking-light lift (shadow + top highlight) with no background — for
    /// surfaces that already supply their own fill.
    func materialLift(radius: CGFloat = Theme.Radii.lg, pressed: Bool = false) -> some View {
        modifier(MaterialLift(radius: radius, pressed: pressed))
    }
    /// Material B — vellum supporting surface, optionally tinted.
    func materialB(tint: MaterialTint = .none, radius: CGFloat = Theme.Radii.md) -> some View {
        modifier(MaterialB(tint: tint, radius: radius))
    }
    /// Material C — pressed specimen; use only for the agentic "noticed" ask.
    func materialC(radius: CGFloat = Theme.Radii.lg) -> some View {
        modifier(MaterialC(radius: radius))
    }
}

// ─── Lightweight elevation (rows / scrolled content) ─────────────────
// Material A is three blurred shadow passes + a plusLighter offscreen pass.
// That cost is fine for a single hero card, but inside a `ForEach`/`ScrollView`
// — where rows realize and re-rasterize together — it's a scroll-jank tax.
// `.cardElevation()` gives ~the same read with ONE shadow and no blend mode.
// Use it for repeated/scrolled rows; reserve Material A for the hero card per
// screen. See PERFORMANCE_REVIEW.md H4.
struct CardElevation: ViewModifier {
    var radius: CGFloat = Theme.Radii.lg
    /// When true, paints the white card fill + clip (drop-in for Material A).
    /// Pass `false` for surfaces that already supply their own background
    /// (e.g. TempoNow's animated aura) so only the shadow is applied.
    var fill: Bool = true
    @ViewBuilder func body(content: Content) -> some View {
        if fill {
            content
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.Palette.card))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(color: inkRule.opacity(0.10), radius: 6, x: 1, y: 4)
        } else {
            content
                .shadow(color: inkRule.opacity(0.10), radius: 6, x: 1, y: 4)
        }
    }
}
extension View {
    /// One-shadow elevation for repeated/scrolled rows. Use instead of
    /// `.materialA()` / `.card()` inside any `ForEach` or `ScrollView`.
    func cardElevation(radius: CGFloat = Theme.Radii.lg, fill: Bool = true) -> some View {
        modifier(CardElevation(radius: radius, fill: fill))
    }
}

// ─── Card surface (v0.3: Material A — no border) ─────────────────────
// `.card()` now resolves to Material A, so every existing call site adopts the
// borderless, shadowed surface with no per-site change.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.Radii.lg
    func body(content: Content) -> some View {
        content.materialA(radius: radius)
    }
}
extension View {
    func card(radius: CGFloat = Theme.Radii.lg) -> some View {
        modifier(CardBackground(radius: radius))
    }
}

// ─── Microlabel (uppercase mono w/ tracking) ─────────────────────────
struct MicroText: View {
    let text: String
    var color: Color = Theme.Palette.inkFaint
    var size: CGFloat = 10.5
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.mono(size, weight: .regular))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

// ─── Button styles ───────────────────────────────────────────────────
struct PrimaryButtonStyle: ButtonStyle {
    var background: Color = Theme.Palette.forest
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.sans(14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(configuration.isPressed ? background.opacity(0.86) : background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous))
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.sans(13))
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Theme.Palette.bgSunk : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radii.sm, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var atlasPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == GhostButtonStyle {
    static var atlasGhost: GhostButtonStyle { GhostButtonStyle() }
}

/// Tactile press scale that matches the prototype's `.pressable` (scale 0.985, 180ms ease-out).
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
extension ButtonStyle where Self == PressScaleStyle {
    static var pressScale: PressScaleStyle { PressScaleStyle() }
}

// ─── Press scale (matches `.pressable`) ──────────────────────────────
struct PressableScale: ViewModifier {
    @State private var pressed = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
    }
}
extension View {
    func pressable() -> some View { modifier(PressableScale()) }
}
