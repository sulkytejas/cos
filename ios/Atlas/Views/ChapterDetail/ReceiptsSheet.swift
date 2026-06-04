import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  ReceiptsSheet.swift — the receipt source sheet (README §7,
//  atlas-trip.css `.receipt-*`).
//
//  Every "cite" / "how I know" element opens this frosted sheet listing
//  the EXACT sources used (email / card swipe / search / health). It
//  slides up from the bottom; tapping the backdrop closes it.
// ════════════════════════════════════════════════════════════════════

/// What a given cite is asking to justify — picks the sheet's title/deck and the
/// subset of receipts shown. `.all` is the full "how I built this" provenance.
enum ReceiptContext: Equatable {
    case all
    case spend
    case route

    var title: String {
        switch self {
        case .all:   return "How I know all this"
        case .spend: return "Where the money came from"
        case .route: return "How I drew the route"
        }
    }
    var deck: String {
        switch self {
        case .all:   return "One email in. Everything else is inference, then live confirmation."
        case .spend: return "Bookings from your inbox, food from your card-swipe SMS. The unbooked legs aren’t counted yet."
        case .route: return "Two cities from one flight email — the hills between them are mine, the trek is yours."
        }
    }
}

struct ReceiptsSheet: View {
    let context: ReceiptContext
    let receipts: [TripReceipt]
    let onClose: () -> Void

    /// Filter the receipts to the ones relevant to this cite.
    private var shown: [TripReceipt] {
        switch context {
        case .all:   return receipts
        case .spend: return receipts.filter { ["EMAIL", "CARD SWIPE"].contains($0.kind) }
        case .route: return receipts.filter { ["EMAIL", "SEARCH", "HEALTH + MAPS"].contains($0.kind) }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0x0D141A).opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .transition(.opacity)

            card
                .transition(.move(edge: .bottom))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Theme.Palette.ink4.opacity(0.6))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)

            Text(context.title)
                .font(Theme.Font.serif(21))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.bottom, 4)
            Text(context.deck)
                .font(Theme.Font.serifItalic(14))
                .foregroundStyle(Theme.Palette.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            ForEach(Array(shown.enumerated()), id: \.element.id) { idx, r in
                ReceiptRow(receipt: r)
                if idx < shown.count - 1 {
                    Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1)
                }
            }

            Text("EVERY FACT TRACES TO ONE OF THESE")
                .font(Theme.Font.mono(9))
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.tealDeep)
                .padding(.top, 12)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                           bottomTrailingRadius: 0, topTrailingRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.5)))
        )
        .shadow(color: Color(hex: 0x141820, opacity: 0.18), radius: 24, x: 0, y: -8)
    }
}

// MARK: - Receipt row (`.receipt-card .src-row`)

private struct ReceiptRow: View {
    let receipt: TripReceipt

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(iconColor)
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.kind.uppercased())
                    .font(Theme.Font.mono(9))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.ink3)
                Text(receipt.ref)
                    .font(Theme.Font.serif(13.5))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    private var iconColor: Color {
        switch receipt.icon {
        case "email":  return Theme.Palette.tealDeep
        case "card":   return Theme.Palette.ink
        case "search": return Theme.Palette.warn      // ember
        case "health": return Theme.Palette.forest
        case "voice":  return Theme.Palette.forest
        default:       return Theme.Palette.ink
        }
    }
}
