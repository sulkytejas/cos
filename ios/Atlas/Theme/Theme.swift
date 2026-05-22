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

// ─── Card surface ────────────────────────────────────────────────────
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.Radii.md
    func body(content: Content) -> some View {
        content
            .background(Theme.Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
    }
}
extension View {
    func card(radius: CGFloat = Theme.Radii.md) -> some View {
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
