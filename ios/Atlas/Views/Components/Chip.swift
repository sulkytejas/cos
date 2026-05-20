import SwiftUI

enum ChipTone {
    case neutral
    case moss
    case ember
}

struct Chip: View {
    let text: String
    var tone: ChipTone = .neutral
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
            }
            Text(text.uppercased())
                .font(Theme.Font.mono(10, weight: .medium))
                .tracking(0.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(border, lineWidth: 0.5)
        )
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Theme.Palette.inkSecondary
        case .moss: return Theme.Palette.moss
        case .ember: return Theme.Palette.ember
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return Theme.Palette.paper
        case .moss: return Theme.Palette.moss.opacity(0.05)
        case .ember: return Theme.Palette.ember.opacity(0.05)
        }
    }

    private var border: Color {
        switch tone {
        case .neutral: return Theme.Palette.borderWarm
        case .moss: return Theme.Palette.moss
        case .ember: return Theme.Palette.ember
        }
    }
}

#Preview {
    HStack {
        Chip(text: "trip")
        Chip(text: "blocks", tone: .ember)
        Chip(text: "enables", tone: .moss)
    }
    .padding()
    .background(Theme.Palette.paper)
}
