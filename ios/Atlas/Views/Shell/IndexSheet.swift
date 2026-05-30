import SwiftUI

/// The logo-menu wayfinding sheet: a frosted panel that slides down from the
/// top listing every surface except the current one. Tap a row to navigate,
/// tap the backdrop to dismiss. Caller animates `isPresented` with
/// `Theme.Motion.overshoot()`.
struct IndexSheet: View {
    let current: AyumiPage
    let onSelect: (AyumiPage) -> Void
    let onClose: () -> Void

    private var destinations: [AyumiPage] { AyumiPage.allCases.filter { $0 != current } }
    private var sheetShape: some Shape {
        UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 22,
                               bottomTrailingRadius: 22, topTrailingRadius: 32, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: 0x0D141A)
                .opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .transition(.opacity)

            sheetCard
                .padding(.horizontal, 22)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var sheetCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GO TO")
                .font(Theme.Font.mono(9))
                .tracking(1.8)
                .foregroundStyle(Theme.Palette.ink3)
                .padding(.bottom, 14)

            ForEach(Array(destinations.enumerated()), id: \.element) { idx, page in
                Button { onSelect(page) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(page.title)
                            .font(Theme.Font.serifItalic(24))
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer(minLength: 12)
                        Text(page.subtitle)
                            .font(Theme.Font.mono(9.5))
                            .tracking(0.57)
                            .foregroundStyle(Theme.Palette.ink3)
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if idx < destinations.count - 1 {
                    Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1)
                }
            }
        }
        .padding(.top, 56)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                sheetShape.fill(.ultraThinMaterial)
                sheetShape.fill(Color.white.opacity(0.62))
            }
        }
        .clipShape(sheetShape)
        .overlay(alignment: .bottom) {
            Capsule().fill(Theme.Palette.ink4.opacity(0.5))
                .frame(width: 40, height: 4)
                .padding(.bottom, 10)
        }
        .shadow(color: Color(hex: 0x141820, opacity: 0.22), radius: 20, x: 0, y: 18)
    }
}
