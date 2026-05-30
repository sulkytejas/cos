import SwiftUI

/// The top-left brand mark + logo-menu trigger: serif-italic "A", a mono crumb
/// "AYUMI · <SCREEN> ▾", a teal date crumb, and a small breathing teal caret
/// that signals it's tappable. Tap → opens the index sheet.
struct AppMark: View {
    let screen: String
    var date: String = ""
    let onTap: () -> Void

    @State private var breathe = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("A")
                    .font(Theme.Font.serifItalic(22))
                    .foregroundStyle(Theme.Palette.ink)
                    .tracking(-0.44)

                Text("AYUMI · \(screen.uppercased()) ▾")
                    .font(Theme.Font.mono(9.5))
                    .tracking(1.5)
                    .foregroundStyle(Theme.Palette.ink3)

                if !date.isEmpty {
                    Text(date)
                        .font(Theme.Font.mono(9.5))
                        .tracking(0.38)
                        .foregroundStyle(Theme.Palette.tealDeep)
                }

                Circle()
                    .fill(Theme.Palette.teal)
                    .frame(width: 4, height: 4)
                    .opacity(breathe ? 0.7 : 0.0)
                    .offset(y: -1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            // 2.6s full cycle (1.3s each way).
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}
