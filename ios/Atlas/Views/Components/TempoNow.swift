import SwiftUI

/// "Now Playing" hero + day rail. Replaces HourRibbon on Today.
/// Tracks live wall clock, surfaces the current/next event in the hero,
/// supports scrub-on-rail and tap-to-pin via the glyph row.
struct TempoNow: View {
    let events: [HourEvent]
    let todoHours: [Double]

    private let startHour: Double = 6
    private let endHour: Double = 24
    private var span: Double { endHour - startHour }

    @State private var pinnedID: UUID? = nil
    @State private var scrubHour: Double? = nil

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { ctx in
            let wallH = currentHour(ctx.date)
            let cursorH = scrubHour ?? wallH
            let (focus, mode) = resolveFocus(cursorH: cursorH)
            let headerLabel = headerLabel(for: mode)

            VStack(spacing: 0) {
                header(label: headerLabel, wallTime: ctx.date)
                heroCard(event: focus, mode: mode, cursorH: cursorH)
                dayRail(events: events,
                        cursorH: cursorH,
                        focus: focus,
                        isScrubbing: scrubHour != nil)
            }
        }
        .padding(.horizontal, 22)
    }

    // ─── Header ───────────────────────────────────────────────────
    private func header(label: String, wallTime: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            MicroText(text: label)
            Spacer()
            Text(timeLabel(currentHour(wallTime), includeSeconds: true))
                .font(Theme.Font.mono(10.5))
                .foregroundStyle(Theme.Palette.inkFaint)
                .tracking(0.6)
        }
        .padding(.bottom, 12)
    }

    // ─── Hero card ────────────────────────────────────────────────
    @ViewBuilder
    private func heroCard(event: HourEvent?, mode: FocusMode, cursorH: Double) -> some View {
        // Content sizes the card; aura + arc live in the background so they
        // paint behind without inflating the card's height.
        VStack(spacing: 0) {
                // Mono time tag
                Text(event?.time ?? "—")
                    .font(Theme.Font.mono(10))
                    .tracking(1.8)
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .padding(.bottom, 10)

                // Title with shimmer
                ZStack {
                    Text(mode == .open ? "Open block" : (event?.title ?? "No events"))
                        .font(Theme.Font.serifItalic(32))
                        .foregroundStyle(Theme.Palette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .breathing()
                        .overlay(
                            // Shimmer sweep, masked to the glyph shapes
                            Group {
                                if event != nil {
                                    ShimmerOverlay()
                                        .mask(
                                            Text(event?.title ?? "")
                                                .font(Theme.Font.serifItalic(32))
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, 8)
                                        )
                                        .allowsHitTesting(false)
                                }
                            }
                        )
                }
                .frame(maxWidth: 280)

                // Meta line
                if let m = event?.meta, mode != .open {
                    Text(m)
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Palette.inkFaint)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.top, 18)
                }

            // Status line
            HStack(spacing: 10) {
                if mode == .active, let ev = event {
                    ProgressArc(pct: progressPct(event: ev, cursorH: cursorH))
                        .frame(width: 22, height: 22)
                }
                Text(statusLabel(event: event, mode: mode, cursorH: cursorH))
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.tealDeep)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        // Single background layer: white surface, then aura on top of it,
        // then the slow rotating arc. The whole stack is clipped to the
        // card's rounded shape so nothing bleeds out, but heights are still
        // driven by the content above.
        .background {
            ZStack {
                Theme.Palette.card                                          // white surface
                BreathingAura().frame(width: 380, height: 380)              // teal orb
                RotatingArc().frame(width: 240, height: 240)                // hairline arc
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        )
    }

    // ─── Day rail ─────────────────────────────────────────────────
    @ViewBuilder
    private func dayRail(events: [HourEvent], cursorH: Double, focus: HourEvent?, isScrubbing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                MicroText(text: "Today's flow")
                Spacer()
                Text(isScrubbing ? "SCRUBBING" : "06 → 24")
                    .font(Theme.Font.mono(9.5))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.inkFainter)
            }
            .padding(.top, 16)

            GeometryReader { geo in
                let usableWidth = geo.size.width
                let xFor: (Double) -> CGFloat = { h in
                    let clamped = min(max(h, self.startHour), self.endHour)
                    return CGFloat((clamped - self.startHour) / self.span) * usableWidth
                }

                ZStack(alignment: .topLeading) {
                    // Glyph row
                    ForEach(events) { ev in
                        let isFocus = focus?.id == ev.id
                        let isPast = ev.endHour < cursorH
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                pinnedID = ev.id
                                scrubHour = nil
                            }
                        } label: {
                            Text(ev.glyph)
                                .font(Theme.Font.serifItalic(isFocus ? 22 : 16))
                                .foregroundStyle(
                                    isPast ? Theme.Palette.inkFainter
                                    : (isFocus ? Theme.Palette.tealDeep : Theme.Palette.inkSecondary)
                                )
                        }
                        .buttonStyle(.plain)
                        .position(x: xFor(ev.startHour), y: 12)
                        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: focus?.id)
                    }
                }
                .frame(height: 26)

                // Rail line + cursor + ticks
                ZStack {
                    // Base hairline
                    Rectangle()
                        .fill(Theme.Palette.hairline)
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .center)

                    // Filled past portion
                    Path { p in
                        let clamped = min(max(cursorH, startHour), endHour)
                        let pct = (clamped - startHour) / span
                        p.move(to: CGPoint(x: 0, y: 9))
                        p.addLine(to: CGPoint(x: CGFloat(pct) * usableWidth, y: 9))
                    }
                    .stroke(Theme.Palette.teal, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .animation(isScrubbing ? .none : .linear(duration: 1.0), value: cursorH)

                    // Hour ticks
                    ForEach(0...Int(span), id: \.self) { i in
                        let h = startHour + Double(i)
                        let showLabel = Int(h) % 6 == 0 && h <= 24
                        VStack(spacing: 1) {
                            Rectangle()
                                .fill(Theme.Palette.hairline)
                                .frame(width: 1, height: showLabel ? 8 : 4)
                            if showLabel {
                                Text(String(format: "%02d", Int(h)))
                                    .font(Theme.Font.mono(9))
                                    .foregroundStyle(Theme.Palette.inkFainter)
                            } else {
                                Spacer().frame(height: 11)
                            }
                        }
                        .position(x: xFor(h), y: showLabel ? 13 : 9)
                    }

                    // Cursor dot
                    let cursorX = xFor(cursorH)
                    Circle()
                        .fill(Theme.Palette.teal)
                        .frame(width: 8, height: 8)
                        .overlay(PulseRing())
                        .position(x: cursorX, y: 9)
                        .allowsHitTesting(false)
                        .animation(isScrubbing ? .none : .linear(duration: 1.0), value: cursorH)
                }
                .frame(height: 22)
                .offset(y: 26)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let pct = max(0, min(1, value.location.x / usableWidth))
                            scrubHour = startHour + Double(pct) * span
                            pinnedID = nil
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                scrubHour = nil
                            }
                        }
                )

                // Todo deadline dots
                ZStack(alignment: .topLeading) {
                    ForEach(Array(todoHours.enumerated()), id: \.offset) { _, h in
                        Circle()
                            .strokeBorder(Theme.Palette.forest, lineWidth: 1)
                            .frame(width: 5, height: 5)
                            .position(x: xFor(h), y: 5)
                    }
                }
                .frame(height: 10)
                .offset(y: 54)
            }
            .frame(height: 70)
        }
    }

    // ─── Focus resolution ─────────────────────────────────────────
    enum FocusMode { case active, upnext, pinned, open }

    private func resolveFocus(cursorH: Double) -> (HourEvent?, FocusMode) {
        if let pid = pinnedID, let pinned = events.first(where: { $0.id == pid }) {
            return (pinned, .pinned)
        }
        if let active = events.first(where: { cursorH >= $0.startHour && cursorH < $0.endHour }) {
            return (active, .active)
        }
        if let up = events.first(where: { $0.startHour > cursorH }) {
            return (up, .upnext)
        }
        if let last = events.last { return (last, .upnext) }
        return (nil, .open)
    }

    private func headerLabel(for mode: FocusMode) -> String {
        switch mode {
        case .active: return "Now playing"
        case .upnext: return "Up next"
        case .pinned: return "Pinned"
        case .open:   return "Open block"
        }
    }

    private func progressPct(event: HourEvent, cursorH: Double) -> Double {
        let total = event.endHour - event.startHour
        guard total > 0 else { return 0 }
        return max(0, min(1, (cursorH - event.startHour) / total))
    }

    private func statusLabel(event: HourEvent?, mode: FocusMode, cursorH: Double) -> String {
        guard let ev = event else { return "" }
        switch mode {
        case .active:
            let minLeft = max(0, Int((ev.endHour - cursorH) * 60))
            return "ends in \(minLeft)m"
        case .upnext:
            let minTo = max(0, Int((ev.startHour - cursorH) * 60))
            return "starts in \(minTo)m"
        case .pinned:
            return ev.time
        case .open:
            return ""
        }
    }

    private func currentHour(_ date: Date) -> Double {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second], from: date)
        let h = Double(comps.hour ?? 0)
        let m = Double(comps.minute ?? 0) / 60.0
        let s = Double(comps.second ?? 0) / 3600.0
        return h + m + s
    }

    private func timeLabel(_ h: Double, includeSeconds: Bool = false) -> String {
        let hh = Int(h)
        let mm = Int((h - Double(hh)) * 60)
        if includeSeconds {
            let ss = Int((h - Double(hh) - Double(mm) / 60.0) * 3600)
            return String(format: "%02d:%02d:%02d", hh, mm, max(0, ss))
        }
        return String(format: "%02d:%02d", hh, mm)
    }
}

// ─── Breathing aura ─────────────────────────────────────────────────
/// Two-layer pulsing orb:
///  • Outer halo (soft, wide) breathes scale 0.92 → 1.12 and opacity 0.55 → 1.0
///    over a ~3.4s cycle.
///  • Inner core (tighter, brighter) pulses slightly faster so the centre
///    feels alive even when the outer halo is at its dim phase.
/// Both rotate slowly so the soft anisotropies in the gradient stops drift.
struct BreathingAura: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate

            // Outer halo — slow, wide, dramatic
            let outerPhase = sin(t * (2 * .pi / 3.4))
            let outerScale = 1.02 + outerPhase * 0.10        // 0.92 → 1.12
            let outerOpacity = 0.78 + outerPhase * 0.22       // 0.56 → 1.00
            let rotation = (t.truncatingRemainder(dividingBy: 36)) / 36 * 360

            // Inner core — faster, tighter
            let innerPhase = sin(t * (2 * .pi / 2.6))
            let innerScale = 1.00 + innerPhase * 0.08         // 0.92 → 1.08
            let innerOpacity = 0.70 + innerPhase * 0.30       // 0.40 → 1.00

            ZStack {
                // Outer halo
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Theme.Palette.teal.opacity(0.32), location: 0.00),
                                .init(color: Theme.Palette.teal.opacity(0.12), location: 0.42),
                                .init(color: Color.clear,                       location: 0.70),
                            ]),
                            center: .center, startRadius: 0, endRadius: 190
                        )
                    )
                    .scaleEffect(outerScale)
                    .opacity(outerOpacity)
                    .rotationEffect(.degrees(rotation))

                // Inner brighter core — sits on top of the halo
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Theme.Palette.teal.opacity(0.40), location: 0.00),
                                .init(color: Theme.Palette.teal.opacity(0.10), location: 0.45),
                                .init(color: Color.clear,                       location: 0.78),
                            ]),
                            center: .center, startRadius: 0, endRadius: 110
                        )
                    )
                    .scaleEffect(innerScale)
                    .opacity(innerOpacity)
                    .rotationEffect(.degrees(-rotation))
            }
        }
    }
}

// ─── Slow rotating hairline arc ─────────────────────────────────────
struct RotatingArc: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let rotation = -(t.truncatingRemainder(dividingBy: 28)) / 28 * 360

            ZStack {
                // Outer arc
                Circle()
                    .strokeBorder(
                        Theme.Palette.teal,
                        style: StrokeStyle(lineWidth: 0.6, lineCap: .round, dash: [3, 320])
                    )
                    .opacity(0.55)
                // Inner dashed ring
                Circle()
                    .inset(by: 26)
                    .strokeBorder(
                        Theme.Palette.teal,
                        style: StrokeStyle(lineWidth: 0.5, lineCap: .round, dash: [2, 18])
                    )
                    .opacity(0.20)
            }
            .rotationEffect(.degrees(rotation))
        }
    }
}

// ─── Shimmer overlay ────────────────────────────────────────────────
struct ShimmerOverlay: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: false)) { ctx in
            let cycle: Double = 6.5
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
            let opacity = shimmerOpacity(at: t)
            // Sweep moves left-to-right across the mask
            let pos = -0.5 + t * 2.0      // -0.5 → 1.5 over the cycle

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.clear,                            location: 0.00),
                    .init(color: Theme.Palette.teal.opacity(0.65),       location: 0.50),
                    .init(color: Color.clear,                            location: 1.00),
                ]),
                startPoint: UnitPoint(x: pos - 0.18, y: 0.3),
                endPoint:   UnitPoint(x: pos + 0.18, y: 0.7)
            )
            .blendMode(.plusLighter)
            .opacity(opacity)
        }
    }

    private func shimmerOpacity(at t: Double) -> Double {
        // off 0–15%, ramp on, hold, ramp off, off until next cycle
        if t < 0.12 { return 0 }
        if t < 0.18 { return (t - 0.12) / 0.06 }
        if t < 0.62 { return 1 }
        if t < 0.72 { return 1 - (t - 0.62) / 0.10 }
        return 0
    }
}

// ─── Pulsing ring around the now-cursor dot ─────────────────────────
struct PulseRing: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = sin(t * .pi) // 2s cycle
            let r = 4 + phase * 4
            let opacity = 0.18 - phase * 0.12
            Circle()
                .stroke(Theme.Palette.teal.opacity(opacity), lineWidth: r)
        }
    }
}

// ─── Progress arc inside the hero (active mode) ─────────────────────
struct ProgressArc: View {
    let pct: Double
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1.4)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, pct)))
                .stroke(
                    Theme.Palette.teal,
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1.0), value: pct)
        }
    }
}

// ─── Title breathing scale (echoes the .breathe class) ──────────────
struct BreathingScale: ViewModifier {
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let s = 1.0 + sin(t * (2 * .pi / 5.5)) * 0.006
            content.scaleEffect(s, anchor: .center)
        }
    }
}
extension View {
    func breathing() -> some View { modifier(BreathingScale()) }
}
