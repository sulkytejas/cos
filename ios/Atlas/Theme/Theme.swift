import SwiftUI

enum Theme {
    enum Palette {
        static let paper = Color("ColorPaper")
        static let card = Color("ColorCard")
        static let borderWarm = Color("ColorBorderWarm")
        static let borderWarmStrong = Color("ColorBorderWarmStrong")
        static let ink = Color("ColorInk")
        static let inkSecondary = Color("ColorInkSecondary")
        static let inkFaint = Color("ColorInkFaint")
        static let moss = Color("ColorMoss")
        static let mossSoft = Color("ColorMossSoft")
        static let ember = Color("ColorEmber")
        static let emberSoft = Color("ColorEmberSoft")
    }

    enum Font {
        static func serif(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .serif)
        }

        static func sans(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .default)
        }

        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        static let title = serif(34, weight: .regular)
        static let titleLarge = serif(46, weight: .regular)
        static let heading = serif(24, weight: .regular)
        static let body = sans(15)
        static let bodyMuted = sans(14)
        static let label = sans(13)
        static let metaUpper = mono(10, weight: .medium)
        static let metaSmall = mono(11)
    }

    enum Radii {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }
}

struct Hairline: View {
    var horizontal: Bool = true
    var body: some View {
        Theme.Palette.borderWarm
            .frame(maxWidth: horizontal ? .infinity : 1,
                   maxHeight: horizontal ? 1 : .infinity)
            .frame(height: horizontal ? 1 : nil)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radii.lg, style: .continuous)
                    .strokeBorder(Theme.Palette.borderWarm, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.sans(14, weight: .medium))
            .foregroundStyle(Theme.Palette.paper)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                configuration.isPressed ? Theme.Palette.mossSoft : Theme.Palette.moss
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.sans(14))
            .foregroundStyle(Theme.Palette.inkSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                configuration.isPressed
                    ? Theme.Palette.borderWarm
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var atlasPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var atlasGhost: GhostButtonStyle { GhostButtonStyle() }
}
