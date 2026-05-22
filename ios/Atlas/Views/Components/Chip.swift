import SwiftUI

// Legacy tone chip retained for backwards compat (still referenced by older code paths).
enum ChipTone {
    case neutral, moss, ember
}

struct Chip: View {
    let text: String
    var tone: ChipTone = .neutral
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9))
            }
            Text(text.uppercased())
                .font(Theme.Font.mono(10, weight: .medium))
                .tracking(0.5)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(border, lineWidth: 0.5))
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Theme.Palette.inkSecondary
        case .moss: return Theme.Palette.forest
        case .ember: return Theme.Palette.teal
        }
    }
    private var background: Color {
        switch tone {
        case .neutral: return Theme.Palette.paper
        case .moss: return Theme.Palette.forestSoft
        case .ember: return Theme.Palette.tealSoft
        }
    }
    private var border: Color {
        switch tone {
        case .neutral: return Theme.Palette.hairline
        case .moss: return Theme.Palette.forest
        case .ember: return Theme.Palette.teal
        }
    }
}
