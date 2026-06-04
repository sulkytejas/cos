import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  RouteTimeline.swift — the vertical route (README §2, atlas-trip.css
//  `.route` / `.stop` / `.leg`).
//
//  Stops joined by legs down a single rail:
//   • .done  (past)     — COLLAPSED to a one-line italic `.mini` + chevron;
//                          tap to expand to the full note + provenance tags.
//   • .here  (current)  — pulsing teal pin, always fully expanded.
//   • .upcoming (future)— hollow pin, always expanded.
//  Legs carry a mode, a "why" reasoning line and a fare. Unbooked legs are
//  styled as suggestions (`.leg.suggest`) with Options / Hold-seat + profile-
//  aware reasoning. Past legs carry a 26px circular PENCIL button (`.update`)
//  that opens a correction WITHOUT toggling the stop's collapse.
// ════════════════════════════════════════════════════════════════════

struct RouteTimeline: View {
    let stops: [Stop]
    let legs: [Leg]
    /// Which past stops are currently expanded (id set). Parent owns it so the
    /// state survives re-renders / reconciles.
    @Binding var expanded: Set<String>
    /// Open the correction sheet for a past leg id.
    let onCorrect: (String) -> Void
    /// Whether a given leg id has a correction prepared — gates the pencil so it's
    /// never a dead control on a past leg with no seeded correction.
    let canCorrect: (String) -> Bool

    var body: some View {
        // Rail on the left; rows laid out top→bottom (stop, then its outgoing leg).
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { idx, stop in
                StopRow(stop: stop,
                        isExpanded: expanded.contains(stop.id),
                        onToggle: { toggle(stop) },
                        onCorrect: { onCorrect(stop.id) })

                // The outgoing leg to the next stop (if any).
                if let leg = legs.first(where: { $0.fromStop == stop.id }) {
                    let pastLeg = stop.state == .done
                    // The pencil is shown only when this past leg actually has a
                    // correction prepared — no dead controls.
                    LegRow(leg: leg, past: pastLeg,
                           correctable: pastLeg && canCorrect(leg.id),
                           onCorrect: { onCorrect(leg.id) })
                }
            }
        }
        .padding(.leading, 30)
        .overlay(alignment: .topLeading) { rail }
    }

    // The vertical rail — ink (past) → teal (present) → faint (future).
    private var rail: some View {
        Rectangle()
            .fill(LinearGradient(
                stops: [
                    .init(color: Theme.Palette.ink,  location: 0.0),
                    .init(color: Theme.Palette.ink,  location: 0.36),
                    .init(color: Theme.Palette.teal, location: 0.5),
                    .init(color: Theme.Palette.rule, location: 0.64),
                    .init(color: Theme.Palette.rule, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom))
            .frame(width: 1.5)
            .padding(.leading, 8)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    private func toggle(_ stop: Stop) {
        guard stop.isCollapsible else { return }
        withAnimation(Theme.Motion.standard(0.36)) {
            if expanded.contains(stop.id) { expanded.remove(stop.id) }
            else { expanded.insert(stop.id) }
        }
    }
}

// MARK: - Stop row

private struct StopRow: View {
    let stop: Stop
    let isExpanded: Bool
    let onToggle: () -> Void
    let onCorrect: () -> Void

    /// A past stop is "open" only when explicitly expanded; present/future are
    /// always open.
    private var open: Bool { stop.state == .done ? isExpanded : true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1 — pin + place + dates (+ chevron for collapsible past).
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(stop.place)
                    .font(Theme.Font.serif(stop.state == .done ? 18 : 22))
                    .foregroundStyle(stop.state == .here ? Theme.Palette.ink
                                     : (stop.state == .done ? Theme.Palette.ink2 : Theme.Palette.ink2))
                if stop.state == .done {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink4)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .animation(Theme.Motion.overshoot(0.3), value: open)
                }
                Spacer(minLength: 8)
                Text(stop.dates)
                    .font(Theme.Font.mono(9))
                    .tracking(0.4)
                    .foregroundStyle(Theme.Palette.ink3)
                    .fixedSize()
            }

            if open {
                // Full note + provenance tags (present / future / expanded past).
                Text(stop.note)
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                HStack(spacing: 7) {
                    ForEach(stop.provenance) { p in ProvenanceChip(provenance: p) }
                }
                .padding(.top, 9)
                .transition(.opacity)
            } else {
                // Collapsed — the one-line italic `.mini` summary.
                Text(stop.mini)
                    .font(Theme.Font.serifItalic(12.5))
                    .foregroundStyle(Theme.Palette.ink3)
                    .padding(.top, 3)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 22)
        .overlay(alignment: .topLeading) { pin }
        .contentShape(Rectangle())
        // Whole-stop tap toggles collapse (only meaningful for past stops).
        .onTapGesture { if stop.state == .done { onToggle() } }
    }

    // The pin: filled (past), pulsing teal (here), hollow (upcoming).
    private var pin: some View {
        ZStack {
            Circle()
                .fill(stop.state == .done ? Theme.Palette.ink : Theme.Palette.paper)
                .frame(width: 17, height: 17)
                .overlay(Circle().strokeBorder(pinBorder, lineWidth: 2))
                .overlay(pinInner)
                .overlay(stop.state == .here
                    ? Circle().fill(Theme.Palette.teal.opacity(0.14)).frame(width: 25, height: 25)
                    : nil)
        }
        .frame(width: 17, height: 17)
        .offset(x: -29.5, y: 3)
    }
    private var pinBorder: Color {
        switch stop.state {
        case .done:     return Theme.Palette.ink
        case .here:     return Theme.Palette.teal
        case .upcoming: return Theme.Palette.ink4
        }
    }
    @ViewBuilder private var pinInner: some View {
        switch stop.state {
        case .done:
            Circle().fill(Color(hex: 0xFFFCEB)).frame(width: 5, height: 5)
        case .here:
            PulsingPinCore()
        case .upcoming:
            EmptyView()
        }
    }
}

/// The breathing teal core of the current ("here") pin.
private struct PulsingPinCore: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle()
            .fill(Theme.Palette.teal)
            .frame(width: 7, height: 7)
            .opacity(on ? 1 : 0.4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - Leg row

private struct LegRow: View {
    let leg: Leg
    let past: Bool
    /// Whether to render the pencil (a correction is prepared for this past leg).
    let correctable: Bool
    let onCorrect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Mode icon.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.Palette.card)
                .frame(width: 24, height: 24)
                .overlay(Image(systemName: modeIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink2))
                .shadow1()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(leg.mode)
                        .font(Theme.Font.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    if leg.corrected {
                        Text("· YOU TOLD ME")
                            .font(Theme.Font.mono(8))
                            .tracking(0.6)
                            .foregroundStyle(Theme.Palette.jade)
                    }
                }
                // The "why" reasoning — hidden on slim past legs (`.leg.past .why`).
                if !past {
                    Text(leg.why)
                        .font(Theme.Font.serifItalic(12.5))
                        .foregroundStyle(Theme.Palette.ink3)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 6)

            // Right cluster — fare/action + (for past legs) the pencil button.
            HStack(spacing: 9) {
                if leg.isSuggestion {
                    SuggestActions()
                } else {
                    Text(leg.fare)
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Palette.ink2)
                        .fixedSize()
                }
                if correctable {
                    // 26px circular PENCIL — NOT a text button. stopPropagation:
                    // it has its own tap, and the leg row has no toggle, so the
                    // collapse never fires from here. Only shown when a correction
                    // is actually prepared, so it's never a dead control.
                    PencilButton(action: onCorrect)
                }
            }
        }
        .padding(.horizontal, past ? 11 : 12)
        .padding(.vertical, past ? 7 : 9)
        .background(legBackground)
        .padding(.top, -8)
        .padding(.bottom, past ? 12 : 14)
    }

    @ViewBuilder private var legBackground: some View {
        if leg.corrected {
            // `.leg.told` — pale jade fill, forest hairline (highest authority).
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(hex: 0xF1F6F2))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.Palette.forest.opacity(0.18), lineWidth: 1))
        } else if leg.isSuggestion {
            // `.leg.suggest` — transparent, full hairline border.
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.Palette.rule, lineWidth: 1)
        } else {
            // Default leg — sunk paper inset.
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.Palette.paperDeep)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.Palette.ruleSoft, lineWidth: 1))
        }
    }

    private var modeIcon: String {
        let m = leg.mode.lowercased()
        if m.contains("flew") || m.contains("flight") || m.contains("fly") { return "airplane" }
        if m.contains("bus") || m.contains("volvo") { return "bus" }
        if m.contains("train") { return "tram" }
        if m.contains("cab") || m.contains("drove") || m.contains("car") { return "car" }
        return "arrow.down"
    }
}

/// The unbooked-leg actions: `Options` (ghost) + `Hold seat` (dark pill).
private struct SuggestActions: View {
    var body: some View {
        HStack(spacing: 7) {
            Text("OPTIONS")
                .font(Theme.Font.mono(8.5))
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.ink2)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(Theme.Palette.rule, lineWidth: 1))
            Text("HOLD SEAT")
                .font(Theme.Font.mono(8.5))
                .tracking(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(Theme.Palette.ink))
        }
    }
}

/// The 26px circular pencil "update" button (`.update`).
private struct PencilButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Palette.ink3)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Theme.Palette.rule, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
