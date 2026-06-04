import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var tab: AppTab = .today
    @State private var showCapture = false
    @State private var pullProgress: CGFloat = 0   // 0..1.2 (1+ = armed)
    @State private var didKickOffIcons = false
    /// Ticks once a minute so any TimeBand-derived labels (tab name, page
    /// titles, eyebrows) update live when the clock crosses a band boundary
    /// without forcing the user to relaunch.
    @State private var clockTick: Int = 0

    enum AppTab: String, CaseIterable, Identifiable {
        case today, chapters, review, settings
        var id: String { rawValue }
        /// User-visible label. Note the third tab's case is `.review` for code
        /// continuity but the user-facing label shifts with the time of day
        /// (Morning / Afternoon / Evening / Night) via TimeBand.current.
        var label: String {
            switch self {
            case .today: return "Today"
            case .chapters: return "Chapters"
            case .review: return TimeBand.current.tabLabel
            case .settings: return "Settings"
            }
        }
    }

    @State private var chaptersTabFrame: CGRect = .zero

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Palette.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                AtlasHeader(onCapture: { showCapture = true })
                Hairline().opacity(0.5)

                ZStack(alignment: .top) {
                    Group {
                        switch tab {
                        case .today:
                            NavigationStack {
                                TodayView(pullProgress: $pullProgress,
                                          onPullCapture: { showCapture = true },
                                          onOpenMorning: {
                                              withAnimation(.easeInOut(duration: 0.32)) {
                                                  tab = .review
                                              }
                                          })
                            }
                        case .chapters:
                            NavigationStack { ChaptersListView() }
                        case .review:
                            NavigationStack {
                                MorningView(chaptersTabFrame: chaptersTabFrame)
                            }
                        case .settings:
                            NavigationStack { SettingsView() }
                        }
                    }
                    // 320ms fade with slight upward drift between tabs
                    .id(tab)
                    .transition(.opacity.combined(with: .offset(y: 8)))

                    PullIndicator(progress: pullProgress)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.32), value: tab)

                Hairline().opacity(0.5)
                BottomNav(active: $tab, chaptersTabFrame: $chaptersTabFrame)
            }
        }
        // Blur the entire app behind the Capture sheet so the sheet sits on
        // a soft glass field, matching the prototype's backdrop-filter blur.
        .blur(radius: showCapture ? 8 : 0)
        .animation(.easeOut(duration: 0.28), value: showCapture)
        .sheet(isPresented: $showCapture) {
            LegacyCaptureSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(22)
                .presentationBackground(Theme.Palette.paper)
        }
        .task {
            // One-shot: if a Gemini key is present, generate icons for any
            // chapter that doesn't have one yet (or whose title changed).
            guard !didKickOffIcons else { return }
            didKickOffIcons = true
            await IconGenerator.generateMissing(in: modelContext)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            clockTick &+= 1
        }
    }
}

// ───────────────────── Header ─────────────────────
struct AtlasHeader: View {
    let onCapture: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Brand mark — the brushed A from Icon options.html.
            // Per the v0.3 design: same brush, two glyphs (A here, 歩 on splash).
            BrushedA(size: 22)

            Text("Ayumi")
                .font(Theme.Font.serifItalic(22))
                .foregroundStyle(Theme.Palette.ink)
            Text("v0.3")
                .font(Theme.Font.mono(9.5))
                .tracking(1.0)
                .foregroundStyle(Theme.Palette.inkFainter)
                .padding(.top, 4)
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(width: 1, height: 12)
                .padding(.top, 4)
            LiveClock()
                .padding(.top, 4)

            Spacer()

            Button(action: onCapture) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Capture")
                        .font(Theme.Font.sans(12.5))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("⌘K")
                        .font(Theme.Font.mono(9))
                        .foregroundStyle(Theme.Palette.inkFaint)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                        )
                        .padding(.leading, 2)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .foregroundStyle(Theme.Palette.ink)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .pressable()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Theme.Palette.paper)
    }
}

// ───────────────────── Pull-to-capture indicator ─────────────────────
struct PullIndicator: View {
    let progress: CGFloat        // 0..1.x — 1+ means armed
    var body: some View {
        let armed = progress >= 1
        let height: CGFloat = max(0, progress * 80)
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 10))
            Text(armed ? "RELEASE TO CAPTURE" : "PULL TO CAPTURE")
                .font(Theme.Font.mono(10))
                .tracking(1.7)
        }
        .foregroundStyle(armed ? Theme.Palette.teal : Theme.Palette.inkFaint)
        .frame(height: height)
        .opacity(min(progress, 1))
        .clipped()
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.18), value: armed)
    }
}

// ───────────────────── Bottom nav ─────────────────────
struct BottomNav: View {
    @Binding var active: RootView.AppTab
    @Binding var chaptersTabFrame: CGRect

    /// Frame of the active tab's *label* in our coord space — drives the
    /// sliding underline.
    @State private var labelFrames: [RootView.AppTab: CGRect] = [:]
    /// On notification, pulses the Chapters tab once (used by Morning Page's
    /// sentence-fly animation).
    @State private var chaptersPulse: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootView.AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .coordinateSpace(name: "bottomNav")
        .overlay(alignment: .topLeading) {
            // Sliding underline — animates between tabs.
            if let frame = labelFrames[active] {
                Rectangle()
                    .fill(Theme.Palette.ink)
                    .frame(width: frame.width * 0.55, height: 1.5)
                    .offset(
                        x: frame.minX + (frame.width - frame.width * 0.55) / 2,
                        y: frame.maxY + 4
                    )
                    .animation(.spring(response: 0.36, dampingFraction: 0.8), value: active)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Theme.Palette.paper)
    }

    @ViewBuilder
    private func tabButton(_ tab: RootView.AppTab) -> some View {
        let isActive = active == tab
        let isChaptersTab = (tab == .chapters)
        Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                active = tab
            }
        } label: {
            VStack(spacing: 6) {
                navIcon(tab, isActive: isActive)
                    .scaleEffect(isActive ? 1.08 : 1.0)
                    .animation(.spring(response: 0.36, dampingFraction: 0.7), value: isActive)
                    // Chapters tab — one-shot pulse triggered by Morning Page
                    // sentence-fly animation arrival.
                    .scaleEffect(isChaptersTab && chaptersPulse ? 1.18 : 1.0)
                    .background(
                        Group {
                            if isChaptersTab && chaptersPulse {
                                Circle()
                                    .stroke(Theme.Palette.teal, lineWidth: 1.5)
                                    .scaleEffect(2.4)
                                    .opacity(0)
                                    .animation(.easeOut(duration: 1.0), value: chaptersPulse)
                            }
                        }
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.55), value: chaptersPulse)

                Text(tab.label)
                    .font(Theme.Font.serifItalic(13))
                    .foregroundStyle(isActive ? Theme.Palette.ink : Theme.Palette.inkFainter)
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .preference(
                                    key: BottomNavFramePref.self,
                                    value: [tab: g.frame(in: .named("bottomNav"))]
                                )
                        }
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                // Publish the Chapters tab's outer frame in global coords for
                // Morning Page's sentence-fly animation target.
                Group {
                    if isChaptersTab {
                        GeometryReader { g in
                            Color.clear
                                .onAppear {
                                    chaptersTabFrame = g.frame(in: .global)
                                }
                                .onChange(of: g.frame(in: .global)) { _, new in
                                    chaptersTabFrame = new
                                }
                        }
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onPreferenceChange(BottomNavFramePref.self) { dict in
            labelFrames.merge(dict) { _, new in new }
        }
        .onReceive(NotificationCenter.default.publisher(for: .atlasChaptersTabPulse)) { _ in
            chaptersPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                chaptersPulse = false
            }
        }
    }

    @ViewBuilder
    private func navIcon(_ tab: RootView.AppTab, isActive: Bool) -> some View {
        switch tab {
        case .today:     TodayNavIcon(isActive: isActive)
        case .chapters:  ChaptersNavIcon(isActive: isActive)
        case .review:    ReviewNavIcon(isActive: isActive)
        case .settings:  SettingsNavIcon(isActive: isActive)
        }
    }
}

/// Review — the icon shifts with the time of day. Per the v0.3 Night-icon
/// handoff, all four states share the same hairline-stroke recipe as the
/// other nav icons (1-pt stroke, fill: none):
///
///   morning / afternoon / evening → shared sun-arc + a small filled dot
///   positioned on the arc (left / top / right). The arc is identical across
///   the three so the swap reads as "same place, different time".
///   night → hairline crescent moon, with the inner arc's radius computed
///   from the actual current lunar phase.
///
/// The dot rhymes with Today's filled center dot — same family.
struct ReviewNavIcon: View {
    let isActive: Bool
    private var band: TimeBand { TimeBand.current }

    var body: some View {
        let c: Color = isActive ? Theme.Palette.ink : Theme.Palette.inkFainter
        ZStack {
            switch band {
            case .night:
                MoonCrescentShape(phase: TimeBand.moonPhase())
                    .stroke(c, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                    .frame(width: 20, height: 20)
            default:
                SunArc()
                    .stroke(c, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .frame(width: 20, height: 20)
                // Filled dot positioned along the arc. r = 1.8 in the 20×20
                // viewBox; the position changes per band.
                Circle()
                    .fill(c)
                    .frame(width: 3.6, height: 3.6)
                    .position(sunDotPosition(for: band))
            }
        }
        .frame(width: 20, height: 20)
        .animation(.easeInOut(duration: 0.32), value: band)
    }

    /// Dot position inside the 20×20 viewBox for each daytime band.
    /// Coordinates are taken directly from the Night-icon handoff.
    private func sunDotPosition(for band: TimeBand) -> CGPoint {
        switch band {
        case .morning:   return CGPoint(x: 4.5,  y: 10.7)   // sun rising on the left
        case .afternoon: return CGPoint(x: 10,   y: 7.2)    // sun at peak
        case .evening:   return CGPoint(x: 15.5, y: 10.7)   // sun descending on the right
        case .night:     return .zero                       // not used
        }
    }
}

/// SunArc — the shared semicircle the daytime nav icons live on.
/// SVG: `M 3 14 A 7 7 0 0 1 17 14` — an arc centred at (10, 14) with r=7,
/// drawn from the left horizon up over the top to the right horizon.
struct SunArc: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 20.0
        var p = Path()
        p.move(to: CGPoint(x: 3 * s, y: 14 * s))
        // In iOS coords (y down), 180° is left, 0° is right, 270° is the top.
        // Going from 180° → 0° via 270° = counter-clockwise in screen terms.
        p.addArc(
            center: CGPoint(x: 10 * s, y: 14 * s),
            radius: 7 * s,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        return p
    }
}

/// MoonCrescentShape — the canonical handoff path translated to SwiftUI.
///
/// Path recipe (SVG):
///   M cx (cy-r)
///   A r r 0 0 outerSweep cx (cy+r)
///   A innerRx r 0 0 innerSweep cx (cy-r) Z
///
/// where:
///   t = waxing ? (phase*4 - 1) : (3 - phase*4)   // -1 (new) → 0 (qtr) → 1 (full)
///   outerSweep = waxing ? 1 : 0
///   innerSweep = (waxing == (t > 0)) ? 1 : 0
///   innerRx    = |t| * r
///
/// Outer arc is always a half-circle; inner arc is a half-ellipse whose
/// horizontal radius slides with the phase. At full moon innerRx == r so the
/// inner arc coincides with the outer, drawing a complete circle (correct).
/// At new moon they coincide in the opposite direction — also reads as a
/// circle in stroke, which is acceptable since a moon outline at new is the
/// only honest representation.
struct MoonCrescentShape: Shape {
    /// 0 = new · 0.25 = first quarter · 0.5 = full · 0.75 = last quarter
    var phase: Double

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 20.0     // scale to 20×20 viewBox
        let cx: CGFloat = 10 * s
        let cy: CGFloat = 10 * s
        let r:  CGFloat = 7  * s
        let waxing = phase < 0.5
        let t = waxing ? (phase * 4 - 1) : (3 - phase * 4)
        let innerRx = CGFloat(abs(t)) * r

        var p = Path()
        let top = CGPoint(x: cx, y: cy - r)
        let bot = CGPoint(x: cx, y: cy + r)

        // ── Outer arc: half-circle from top to bottom ─────────────────────
        // Waxing crescents have the lit side on the right; waning on the left.
        // SVG outerSweep=1 (waxing) maps to "clockwise on screen", which in
        // SwiftUI's iOS coords means `clockwise: true`.
        p.move(to: top)
        p.addArc(
            center: CGPoint(x: cx, y: cy), radius: r,
            startAngle: .degrees(-90), endAngle: .degrees(90),
            clockwise: !waxing
        )

        // ── Inner arc: half-ellipse from bottom back to top ───────────────
        // Bulge direction depends on the four quadrants of the phase:
        //   waxing crescent (t<0): bulge LEFT (terminator cuts into right half)
        //   waxing gibbous  (t>0): bulge RIGHT
        //   waning gibbous  (t>0): bulge LEFT
        //   waning crescent (t<0): bulge RIGHT
        let bulgeDir: CGFloat = {
            switch (waxing, t > 0) {
            case (true,  false): return -1   // waxing crescent
            case (true,  true):  return  1   // waxing gibbous
            case (false, true):  return -1   // waning gibbous
            case (false, false): return  1   // waning crescent
            }
        }()
        let bulge = bulgeDir * innerRx
        let k: CGFloat = 0.5522847498   // cubic-bezier circle/ellipse constant

        // Half-ellipse via two quarter cubic beziers — SwiftUI Path doesn't
        // expose an elliptical arc directly, so we approximate.
        p.addCurve(
            to: CGPoint(x: cx + bulge, y: cy),
            control1: CGPoint(x: cx + bulge * k, y: bot.y),
            control2: CGPoint(x: cx + bulge,     y: cy + r * k)
        )
        p.addCurve(
            to: top,
            control1: CGPoint(x: cx + bulge,     y: cy - r * k),
            control2: CGPoint(x: cx + bulge * k, y: top.y)
        )
        p.closeSubpath()
        return p
    }
}

// ─── Per-tab icons with draw-on animations ─────────────────────────

/// Today — outer ring traces in from 12 o'clock clockwise, then the centre
/// dot pops with a soft spring.
struct TodayNavIcon: View {
    let isActive: Bool
    @State private var ringTrim: CGFloat = 1
    @State private var dotScale: CGFloat = 0

    private let size: CGFloat = 20

    var body: some View {
        let c: Color = isActive ? Theme.Palette.ink : Theme.Palette.inkFainter
        ZStack {
            // Inactive resting ring — always visible so the tab never disappears
            Circle()
                .strokeBorder(c.opacity(isActive ? 0.0 : 1.0), lineWidth: 1)
                .frame(width: size, height: size)

            // Active overlay — traces in on activation
            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(Theme.Palette.ink, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))  // start at 12 o'clock
                .opacity(isActive ? 1 : 0)

            // Centre dot
            Circle()
                .fill(c)
                .frame(width: 6, height: 6)
                .scaleEffect(dotScale)
        }
        .onAppear { syncToActive(animated: false) }
        .onChange(of: isActive) { _, _ in syncToActive(animated: true) }
    }

    private func syncToActive(animated: Bool) {
        if isActive {
            // Trace the ring + pop the dot
            ringTrim = 0
            withAnimation(animated ? .easeOut(duration: 0.32) : .none) {
                ringTrim = 1
            }
            dotScale = 0
            withAnimation(
                animated
                ? .spring(response: 0.32, dampingFraction: 0.68).delay(0.18)
                : .none
            ) {
                dotScale = 1
            }
        } else {
            withAnimation(animated ? .easeOut(duration: 0.18) : .none) {
                ringTrim = 1
                dotScale = 0
            }
        }
    }
}

/// Chapters — three horizontal lines that extend from width 0 to their
/// target widths with a 60ms stagger top→bottom.
struct ChaptersNavIcon: View {
    let isActive: Bool
    @State private var widths: [CGFloat] = [16, 16, 10]
    @State private var hasAppeared = false

    private let targets: [CGFloat] = [16, 16, 10]

    var body: some View {
        let c: Color = isActive ? Theme.Palette.ink : Theme.Palette.inkFainter
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(c)
                    .frame(width: widths[i], height: 1)
            }
        }
        .frame(width: 20, height: 20, alignment: .center)
        .onAppear {
            if !hasAppeared { widths = targets; hasAppeared = true }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue { animateExtend() }
        }
    }

    /// Reset to 0 and animate each line out to its target with stagger.
    private func animateExtend() {
        widths = [0, 0, 0]
        for i in 0..<3 {
            withAnimation(.easeOut(duration: 0.32).delay(Double(i) * 0.06)) {
                widths[i] = targets[i]
            }
        }
    }
}

/// Settings — two small circles connected by lines (top-left ⟶ right, bottom
/// ⟵ middle-left). Lines extend from one circle to the other on activation;
/// circles ease in slightly behind them.
struct SettingsNavIcon: View {
    let isActive: Bool
    @State private var lineTrim: CGFloat = 1
    @State private var circleScale: CGFloat = 1

    var body: some View {
        let c: Color = isActive ? Theme.Palette.ink : Theme.Palette.inkFainter
        ZStack {
            // Top row: small circle on left, line extending right
            Group {
                Circle()
                    .strokeBorder(c, lineWidth: 1)
                    .frame(width: 6, height: 6)
                    .offset(x: -6, y: -6)
                    .scaleEffect(circleScale, anchor: .center)
                LineExtender(trim: lineTrim)
                    .stroke(c, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .frame(width: 9, height: 1)
                    .offset(x: 4, y: -6)
            }
            // Bottom row: line extending right, small circle on right
            Group {
                LineExtender(trim: lineTrim, flipped: true)
                    .stroke(c, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .frame(width: 9, height: 1)
                    .offset(x: -4, y: 6)
                Circle()
                    .strokeBorder(c, lineWidth: 1)
                    .frame(width: 6, height: 6)
                    .offset(x: 6, y: 6)
                    .scaleEffect(circleScale, anchor: .center)
            }
        }
        .frame(width: 20, height: 20)
        .onChange(of: isActive) { _, newValue in
            if newValue { animateExtend() }
        }
    }

    private func animateExtend() {
        circleScale = 0
        lineTrim = 0
        withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
            circleScale = 1
        }
        withAnimation(.easeOut(duration: 0.34).delay(0.08)) {
            lineTrim = 1
        }
    }
}

/// A horizontal line shape with a configurable trim (0 = nothing, 1 = full).
/// Used so we can animate the line drawing on from one end.
private struct LineExtender: Shape {
    var trim: CGFloat
    var flipped: Bool = false
    var animatableData: CGFloat {
        get { trim }
        set { trim = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let length = rect.width * trim
        if flipped {
            p.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX - length, y: rect.midY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX + length, y: rect.midY))
        }
        return p
    }
}

private struct BottomNavFramePref: PreferenceKey {
    static let defaultValue: [RootView.AppTab: CGRect] = [:]
    static func reduce(value: inout [RootView.AppTab: CGRect], nextValue: () -> [RootView.AppTab: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
