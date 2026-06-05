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
                           route: routeLine(for: leg),
                           correctable: pastLeg && canCorrect(leg.id),
                           onCorrect: { onCorrect(leg.id) })
                }
            }
        }
        .padding(.leading, 30)
        // The rail sits BEHIND the stop rows so the pins composite over it: the
        // 1.5pt rail stroke (x≈8–9.5pt) and the done-stop pin center (x≈9pt) share
        // the same x, so an `.overlay` rail drew the stroke straight through the
        // pin's cream center dot (CSS `.stop.done .pin::after { 5px #fffceb }`),
        // reading as a split "keyhole". `.background` keeps the rail under the pin
        // so the dot stays an opaque round 5pt cream dot, as the reference shows.
        .background(alignment: .topLeading) { rail }
    }

    /// "Delhi → Nainital" for a leg, looked up from the stop place names. Empty if
    /// either endpoint is missing.
    private func routeLine(for leg: Leg) -> String {
        guard let from = stops.first(where: { $0.id == leg.fromStop })?.place,
              let to = stops.first(where: { $0.id == leg.toStop })?.place else { return "" }
        return "\(from) → \(to)"
    }

    // The vertical rail — ink (past) → teal (present), held through and below the
    // active node (the ref keeps a consistent ink/teal stroke with no gray fade).
    private var rail: some View {
        Rectangle()
            .fill(LinearGradient(
                stops: [
                    .init(color: Theme.Palette.ink,  location: 0.0),
                    .init(color: Theme.Palette.ink,  location: 0.36),
                    .init(color: Theme.Palette.teal, location: 0.5),
                    .init(color: Theme.Palette.teal, location: 1.0),
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
            // Row 1 — pin + place … right-aligned mono meta … trailing chevron.
            // The disclosure chevron sits at the FAR right, after the date meta
            // (ref: "Delhi … May 30 · DEL  ›").
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(stop.place)
                    .font(Theme.Font.serif(stop.state == .done ? 18 : 22))
                    .foregroundStyle(stop.state == .here ? Theme.Palette.ink
                                     : (stop.state == .done ? Theme.Palette.ink2 : Theme.Palette.ink2))
                Spacer(minLength: 8)
                Text(stop.dates)
                    .font(Theme.Font.mono(9))
                    .tracking(0.4)
                    .foregroundStyle(Theme.Palette.ink3)
                    .fixedSize()
                if stop.state == .done {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink4)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .animation(Theme.Motion.overshoot(0.3), value: open)
                }
            }

            if open {
                // Full note + provenance tags (present / future / expanded past).
                Text(stop.note)
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.ink2)
                    // CSS `.note { line-height: 1.4 }` = 19.6pt at 14pt. SwiftUI
                    // `.lineSpacing` is the additive gap on top of the font's
                    // intrinsic line box (Instrument Serif ≈18.2pt at 14pt), so
                    // ~1.4 lands the 19.6pt box; the prior `2` over-extended each
                    // 2-line note, compounding a small per-stop downward drift down
                    // the rail (sim pin pitch ran ~2.7pt long vs ref).
                    .lineSpacing(1.4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                HStack(spacing: 7) {
                    ForEach(stop.provenance) { p in ProvenanceChip(provenance: p) }
                }
                .padding(.top, 9)
                .transition(.opacity)

                // The active ("here") stop carries the live-location action row:
                // a filled pale-teal "YOU'RE HERE · MAPS" pill, a dashed-border
                // teal "STAY ENDS JUN 6" pill, and a small circular edit button.
                if stop.state == .here {
                    HStack(spacing: 7) {
                        Text("YOU’RE HERE · MAPS")
                            .font(Theme.Font.mono(8))
                            .tracking(0.8)                    // CSS .know letter-spacing 0.1em × 8pt
                            .foregroundStyle(Theme.Palette.tealDeep)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)   // CSS .know { white-space:nowrap }
                            .padding(.horizontal, 7).padding(.vertical, 2)  // CSS .know padding 2px 7px
                            .background(Capsule().fill(Theme.Palette.tealSoft))
                        Text("STAY ENDS JUN 6")
                            .font(Theme.Font.mono(8))
                            .tracking(0.8)
                            .foregroundStyle(Theme.Palette.tealDeep)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            // CSS `.know.inferred { border: 1px dashed
                            // rgba(0,87,107,0.45) }` = tealDeep (#00576b) at 0.45
                            // alpha — a muted grey-teal, NOT the full-saturation
                            // --teal #0089a8 which rendered a vivid cyan in-sim. The
                            // CSS `1px dashed` default is a fine even dash≈gap, so
                            // [3,3] matches the cadence (the prior [3,2] gave long
                            // dashes / short gaps). The chip TEXT stays solid
                            // tealDeep (#00576b), which is already correct.
                            .overlay(Capsule().strokeBorder(
                                Theme.Palette.tealDeep.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        Button(action: onCorrect) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.Palette.ink3)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(Theme.Palette.rule, lineWidth: 1))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 9)
                    .transition(.opacity)
                }
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
    //
    // The `.here` pin is a single ring, not a bullseye — CSS `.stop.here .pin`
    // is a 17px white circle with a 2px teal border, a 7px teal `::after` center
    // dot, and `box-shadow: 0 0 0 4px rgba(0,137,168,0.14)`. The soft 4pt halo is
    // a BACKGROUND (behind the white circle) so it never tints/obscures the ring
    // or dot — drawing it as an overlay read as a concentric multi-ring.
    private var pin: some View {
        ZStack {
            Circle()
                .fill(stop.state == .done ? Theme.Palette.ink : Theme.Palette.paper)
                .frame(width: 17, height: 17)
                .background(stop.state == .here
                    ? Circle().fill(Theme.Palette.teal.opacity(0.14)).frame(width: 25, height: 25)
                    : nil)
                .overlay(Circle().strokeBorder(pinBorder, lineWidth: 2))
                .overlay(pinInner)
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
    // The center marker, drawn inside a fixed 17pt box so the overlay centers it
    // crisply on the pin. Earlier the bare conditional `Circle().frame(5×5)` had
    // no stable container in the overlay and rendered as a narrow vertical
    // "keyhole"/zero artifact; pinning it in a centered 17pt frame makes the done
    // marker a true round 5pt #fffceb dot and the here marker a 7pt teal dot, per
    // CSS `.stop.done .pin::after { 5px #fffceb }` / `.stop.here .pin::after { 7px teal }`.
    @ViewBuilder private var pinInner: some View {
        Group {
            switch stop.state {
            case .done:
                Circle().fill(Color(hex: 0xFFFCEB)).frame(width: 5, height: 5)
            case .here:
                PulsingPinCore()
            case .upcoming:
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .frame(width: 17, height: 17, alignment: .center)
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
    /// The "From → To" route line (place names), shown as a second line under the
    /// mode on booked legs (ref: "Flew to Pantnagar ·" / "Delhi → Nainital").
    var route: String = ""
    /// Whether to render the pencil (a correction is prepared for this past leg).
    let correctable: Bool
    let onCorrect: () -> Void

    /// The booked-leg title. PAST legs join the mode + route on one bold dark
    /// line ("Flew to Pantnagar · Delhi → Nainital"), matching the prototype's
    /// single `.mode` element. If `leg.mode` already carries the route (e.g.
    /// "Shared taxi · Nainital → Rishikesh"), it is used as-is to avoid doubling.
    private var pastLegLabel: String {
        guard past, !route.isEmpty, !leg.mode.contains(route), !leg.mode.contains("→")
        else { return leg.mode }
        return "\(leg.mode) · \(route)"
    }

    var body: some View {
        // CSS `.leg { gap:10px }`, but SwiftUI's text measurement runs the bold
        // 12pt mode line ~4pt tighter than the browser, wrapping the route arrow
        // ("→") alone onto line 2 (sim: "Shared taxi · Nainital" / "→ Rishikesh").
        // Trimming the icon→text gap 10 → 8 hands that width back to the `.m`
        // column so "Shared taxi · Nainital →" stays whole on line 1, matching the
        // northindia reference (paired with the past-leg horizontal padding below).
        HStack(spacing: 8) {
            // Mode icon.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.Palette.card)
                .frame(width: 24, height: 24)
                .overlay(modeGlyph)
                .shadow1()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    // Unbooked suggestions title with the route + "· not booked"
                    // (ref: "Rishikesh → Kasol · not booked"); booked legs title
                    // with their mode. PAST booked legs join the mode + route on a
                    // SINGLE bold dark line — CSS markup is one `.mode` element
                    // ("Flew to Pantnagar · Delhi → Nainital") and `.leg.past .why
                    // { display:none }`, so there is no separate gray subtitle.
                    if leg.isSuggestion, !route.isEmpty {
                        (Text("\(route) · ").foregroundColor(Theme.Palette.ink)
                            + Text("not booked").foregroundColor(Theme.Palette.ink3))
                            .font(Theme.Font.sans(12, weight: .semibold))
                    } else {
                        Text(pastLegLabel)
                            .font(Theme.Font.sans(12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    if leg.corrected {
                        Text("· YOU TOLD ME")
                            .font(Theme.Font.mono(8))
                            .tracking(0.6)
                            .foregroundStyle(Theme.Palette.jade)
                    }
                }
                // Unbooked suggestions show the profile-tuned "why" reasoning.
                // Non-past booked legs keep a compact gray route subtitle; PAST
                // booked legs fold the route into the bold title above (no gray
                // subtitle — matches CSS `.leg.past .why { display:none }`).
                if leg.isSuggestion {
                    Text(leg.why)
                        .font(Theme.Font.serifItalic(12.5))
                        .foregroundStyle(Theme.Palette.ink3)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !past, !route.isEmpty {
                    Text(route)
                        .font(Theme.Font.sans(11))
                        .foregroundStyle(Theme.Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // CSS `.leg .m { flex:1; min-width:0 }` — the mode column flexes to
            // take all the space the fare cluster doesn't need, with NO forced
            // gutter. Any minimum here starves the bold 12pt mode line and forces
            // the route arrow ("→") to wrap alone onto line 2 (sim: "Shared taxi ·
            // Nainital" / "→ Rishikesh"); the ref keeps "Shared taxi · Nainital →"
            // whole on line 1. A 0 minimum returns that width so the arrow stays
            // beside its city, matching `min-width:0` with no gutter (ref-northindia).
            Spacer(minLength: 0)

            // Right cluster — fare/action + (for past legs) the pencil button.
            // Tightened 9 → 7 to hand a couple more points back to the mode column
            // so the route arrow clears line 1.
            HStack(spacing: 7) {
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
        // Past legs trim horizontal padding 11 → 9 to give the `.m` mode column a
        // couple more points (with the 10 → 8 icon gap above) so the route arrow
        // clears line 1, matching the reference. Non-past keeps the CSS 12.
        .padding(.horizontal, past ? 9 : 12)
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

    /// The 24pt icon-tile glyph. Transit legs (taxi/shared/bus/volvo) use the
    /// minimal LINE-ART vehicle from the CSS `.leg .ic` SVG (a thin rounded-rect
    /// body + two wheel dots, NOT the filled SF "bus" glyph which renders windows
    /// + mirrors and pushes the label to a 2nd line). Everything else keeps its SF
    /// Symbol.
    @ViewBuilder private var modeGlyph: some View {
        let m = leg.mode.lowercased()
        if m.contains("taxi") || m.contains("shared") || m.contains("bus") || m.contains("volvo") {
            BusGlyph()
                .stroke(Theme.Palette.ink2, lineWidth: 1.2)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: modeIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Palette.ink2)
        }
    }

    private var modeIcon: String {
        let m = leg.mode.lowercased()
        if m.contains("train") { return "tram" }
        // Booked flight legs read as an arrow in the icon tile (ref: the
        // Delhi→Nainital card shows "→", not an airplane).
        if m.contains("flew") || m.contains("flight") || m.contains("fly") { return "arrow.right" }
        if m.contains("cab") || m.contains("drove") || m.contains("car") { return "car" }
        return "arrow.right"
    }
}

/// Minimal line-art vehicle, ported 1:1 from the CSS `.leg .ic` SVG (14×14
/// viewBox): a rounded-rect body (`x1.5 y3 w11 h7 rx1.5`, stroked) + two wheel
/// dots (`cx4/cx10 cy11 r1.2`). Stroked by the caller; the wheels are part of the
/// path so they share the stroke weight (drawn as tiny closed loops that read as
/// filled dots at 1.2pt stroke). Drawn in a 14×14 space.
private struct BusGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 14   // scale a 14-unit design into the frame
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        // Body: rounded rect x1.5 y3 w11 h7 rx1.5.
        p.addRoundedRect(in: CGRect(x: P(1.5, 3).x, y: P(1.5, 3).y, width: 11 * s, height: 7 * s),
                         cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s))
        // Wheels: two small dots. At r0.9 stroked 1.2pt they read as solid wheels.
        p.addEllipse(in: CGRect(x: P(4, 11).x - 0.9 * s, y: P(4, 11).y - 0.9 * s, width: 1.8 * s, height: 1.8 * s))
        p.addEllipse(in: CGRect(x: P(10, 11).x - 0.9 * s, y: P(10, 11).y - 0.9 * s, width: 1.8 * s, height: 1.8 * s))
        return p
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
