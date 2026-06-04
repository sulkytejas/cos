import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  ConnectorsSection.swift — "to serve you better" (README §6,
//  atlas-trip.css `.conn`).
//
//  Two groups: sources Ayumi is ALREADY using (Gmail / Health / Maps —
//  each with a jade "Feeding" pulse) and sources she'd reach for NEXT
//  (HDFC / IRCTC / Calendar — each with a Connect button + a one-line
//  payoff). Granting one flips it to "Linked", rewrites its role copy to
//  what she can now do, and blooms the halo (the parent drives the halo
//  via `onGrant`). This is "progressive capability via consent".
// ════════════════════════════════════════════════════════════════════

struct ConnectorsSection: View {
    let connectors: [Connector]
    /// Connector ids the user has just granted (parent owns the set so the
    /// optimistic relabel survives re-renders).
    @Binding var granted: Set<String>
    /// Fires on grant — the parent calls repo.grantConnector + blooms the halo.
    let onGrant: (Connector) -> Void

    var body: some View {
        ChapterSection(title: "To serve you better") {
            VStack(alignment: .leading, spacing: 0) {
                Text("Three sources already sharpen this chapter. Three more would — each only what it needs, when it needs it.")
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)

                ForEach(Array(connectors.enumerated()), id: \.element.id) { idx, conn in
                    ChapterConnectorRow(connector: conn,
                                        isGranted: granted.contains(conn.id),
                                        onGrant: { grant(conn) })
                    if idx < connectors.count - 1 {
                        Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1)
                    }
                }
            }
        }
    }

    private func grant(_ conn: Connector) {
        guard !granted.contains(conn.id) else { return }
        withAnimation(Theme.Motion.overshoot(0.4)) { _ = granted.insert(conn.id) }
        onGrant(conn)
    }
}

// MARK: - Connector row

private struct ChapterConnectorRow: View {
    let connector: Connector
    let isGranted: Bool
    let onGrant: () -> Void

    /// Once granted (or already feeding) the row shows the "now I can…" role.
    private var feeding: Bool { connector.status == .feeding || isGranted }
    /// After granting, the role rewrites to "what she can now do" (the post-grant
    /// `grantedRole`, mirroring the server's grantCopyFor) — NOT the pre-grant
    /// offer (`unlockCopy`). Falls back to `role` when no grantedRole is seeded.
    private var roleCopy: String {
        if isGranted, !connector.grantedRole.isEmpty { return connector.grantedRole }
        return connector.role
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon swatch — serif initial on the connector's brand colour.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(iconColor)
                .frame(width: 34, height: 34)
                .overlay(Text(initial)
                    .font(Theme.Font.serifItalic(15))
                    .foregroundStyle(.white))
                .opacity(connector.status == .available && !isGranted ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(connector.name)
                    .font(Theme.Font.sans(13.5, weight: .semibold))
                    .foregroundStyle(connector.status == .available && !isGranted
                                     ? Theme.Palette.ink2 : Theme.Palette.ink)
                Text(roleCopy)
                    .font(Theme.Font.serifItalic(12.5))
                    .foregroundStyle(isGranted ? Theme.Palette.jade : Theme.Palette.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // Action — feeding indicator vs Connect / Linked.
            VStack {
                if feeding {
                    if isGranted {
                        LinkedPill()
                    } else {
                        FeedingIndicator()
                    }
                } else {
                    ConnectButton(action: onGrant)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 12)
        .animation(Theme.Motion.standard(0.3), value: isGranted)
    }

    private var iconColor: Color {
        switch connector.icon {
        case "gmail":  return Theme.Palette.tealDeep
        case "health": return Theme.Palette.forest
        case "maps":   return Theme.Palette.warn          // ember
        case "bank":   return Theme.Palette.ink
        case "rail":   return Color(hex: 0xC98A3A)        // sand
        case "cal":    return Theme.Palette.ink2
        default:       return Theme.Palette.ink
        }
    }
    private var initial: String { String(connector.name.prefix(1)) }
}

// MARK: - Action atoms

/// The live jade "Feeding" indicator (`.conn .feeding`).
private struct FeedingIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            LiveDotJade()
            Text("FEEDING")
                .font(Theme.Font.mono(8.5))
                .tracking(0.7)
                .foregroundStyle(Theme.Palette.jade)
        }
    }
}

/// After a grant — the green "Linked" pill (`.connect.linked`).
private struct LinkedPill: View {
    var body: some View {
        Text("LINKED")
            .font(Theme.Font.mono(9))
            .tracking(0.9)
            .foregroundStyle(.white)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Capsule().fill(Theme.Palette.jade))
    }
}

/// The dark "Connect" pill (`.conn .connect`).
private struct ConnectButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("CONNECT")
                .font(Theme.Font.mono(9))
                .tracking(0.9)
                .foregroundStyle(.white)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().fill(Theme.Palette.ink))
        }
        .buttonStyle(.plain)
        .pressable()
    }
}

private struct LiveDotJade: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle()
            .fill(Theme.Palette.jade)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
