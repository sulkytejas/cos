import SwiftUI

/// Map view for chapters. Two states:
///   • Constellation — italic letters at four positions with curved edge labels.
///   • Focused      — the tapped glyph morphs into a drop-cap in the upper-
///                    left and a full chapter detail panel reveals around it
///                    with a staggered fade-up. Tap × (or the drop-cap itself)
///                    to return to the constellation.
struct ConstellationView: View {
    let chapters: [Chapter]
    let edges: [ChapterLink]
    let todos: [Todo]
    @Binding var focusedID: UUID?
    let onOpen: (Chapter) -> Void

    /// Normalized positions per chapter (each 0..1 in canvas space).
    @State private var normPositions: [UUID: CGPoint] = [:]
    @State private var initialised = false
    @State private var gravityID: UUID? = nil
    @State private var longPressTimer: Timer? = nil

    private let CARD_H: CGFloat = 460
    private let INSET: CGFloat = 38      // keeps edge lines off the glyph

    // Drop-cap geometry — where the focused glyph lands in the panel.
    private let dropCapPos = CGPoint(x: 60, y: 88)
    private let dropCapFontSize: CGFloat = 120
    private let restingFontSize: CGFloat = 56

    private var focusedChapter: Chapter? {
        guard let id = focusedID else { return nil }
        return chapters.first(where: { $0.id == id })
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Background — fades out when focused
                backgroundLayer(w: w, h: h)
                    .opacity(focusedID == nil ? 1 : 0)
                    .allowsHitTesting(focusedID == nil)
                    .animation(.easeOut(duration: 0.38), value: focusedID)

                // Glyphs — focused glyph morphs to drop-cap, others fade out
                ForEach(Array(orderedChapters.enumerated()), id: \.element.id) { idx, ch in
                    glyphNode(idx: idx, chapter: ch, canvasW: w, canvasH: h)
                }

                // Focused detail panel (× close, type, title, range, purpose,
                // progress, todos, open-chapter button). Staggered fade-up.
                if let ch = focusedChapter {
                    focusedPanel(chapter: ch, w: w, h: h)
                        .transition(.opacity)
                }

                // Hint (only when not focused)
                if focusedID == nil {
                    Text("TAP · DRAG · HOLD")
                        .font(Theme.Font.mono(8.5))
                        .tracking(1.4)
                        .foregroundStyle(Theme.Palette.inkFainter)
                        .position(x: w - 64, y: h - 14)
                        .transition(.opacity)
                }
            }
            .onAppear { ensureSeeded() }
            .onChange(of: chapters.count) { _, _ in ensureSeeded() }
        }
        .frame(height: CARD_H)
        .materialA()
        .padding(.horizontal, 22)
    }

    // Stable chapter order: by createdAt ascending so quadrants are deterministic.
    private var orderedChapters: [Chapter] {
        chapters.sorted { $0.createdAt < $1.createdAt }
    }

    private func ensureSeeded() {
        guard !initialised || normPositions.count != chapters.count else { return }
        let seeds: [CGPoint] = [
            CGPoint(x: 0.27, y: 0.22),
            CGPoint(x: 0.73, y: 0.34),
            CGPoint(x: 0.27, y: 0.78),
            CGPoint(x: 0.73, y: 0.78),
        ]
        for (i, ch) in orderedChapters.enumerated() {
            normPositions[ch.id] = seeds[i % seeds.count]
        }
        initialised = true
    }

    // ─── Background layer (gravity well + edges) ───────────────────
    @ViewBuilder
    private func backgroundLayer(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            // Gravity well
            Circle()
                .strokeBorder(
                    Theme.Palette.hairline.opacity(0.5),
                    style: StrokeStyle(lineWidth: 0.6, dash: [2, 5])
                )
                .frame(width: 76, height: 76)
            Circle()
                .fill(Theme.Palette.teal)
                .frame(width: 5, height: 5)
            Text("TODAY")
                .font(Theme.Font.mono(8.5))
                .tracking(1.7)
                .foregroundStyle(Theme.Palette.inkFainter)
                .offset(y: 22)
        }
        .position(x: w / 2, y: h / 2)
        .overlay(
            ZStack {
                ForEach(Array(edges.enumerated()), id: \.element.id) { idx, edge in
                    edgeView(edge: edge, index: idx, w: w, h: h)
                }
            }
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func edgeView(edge: ChapterLink, index: Int, w: CGFloat, h: CGFloat) -> some View {
        if let fromID = edge.fromChapter?.id, let toID = edge.toChapter?.id,
           let na = normPositions[fromID], let nb = normPositions[toID] {

            let a = CGPoint(x: na.x * w, y: na.y * h)
            let b = CGPoint(x: nb.x * w, y: nb.y * h)
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(1, sqrt(dx*dx + dy*dy))
            let ux = dx / len, uy = dy / len
            let a2 = CGPoint(x: a.x + ux * INSET, y: a.y + uy * INSET)
            let b2 = CGPoint(x: b.x - ux * INSET, y: b.y - uy * INSET)
            let px = -uy, py = ux
            let mag = magnitudeFor(edge.relation)
            let signed: CGFloat = index.isMultiple(of: 2) ? mag : -mag
            let curveAmp = signed * min(len * 0.6, 130)
            let mid = CGPoint(x: (a2.x + b2.x) / 2 + px * curveAmp,
                              y: (a2.y + b2.y) / 2 + py * curveAmp)
            let color = edgeColor(edge)
            let dash: [CGFloat] = edge.relation == .conflicts ? [3, 3] : []

            Path { p in
                p.move(to: a2)
                p.addQuadCurve(to: b2, control: mid)
            }
            .stroke(color, style: StrokeStyle(lineWidth: 0.8, lineCap: .round, dash: dash))
            .opacity(0.75)

            CurvedLabel(
                text: edge.relation.rawValue,
                start: a2, end: b2, control: mid,
                color: color
            )
        }
    }

    // ─── Glyph node ───────────────────────────────────────────────
    @ViewBuilder
    private func glyphNode(idx: Int, chapter ch: Chapter, canvasW w: CGFloat, canvasH h: CGFloat) -> some View {
        let isFocused = focusedID == ch.id
        let isOtherFocused = focusedID != nil && focusedID != ch.id
        let isGravity = gravityID == ch.id
        let np = normPositions[ch.id] ?? CGPoint(x: 0.5, y: 0.5)
        let restingPos = CGPoint(x: np.x * w, y: np.y * h)
        let pos = isFocused ? dropCapPos : restingPos
        let fontSize = isFocused ? dropCapFontSize : restingFontSize
        let scale: CGFloat = isFocused ? 1 : (isGravity ? 1.25 : 1)

        ZStack {
            if isGravity && focusedID == nil {
                Circle()
                    .strokeBorder(
                        Theme.Palette.teal,
                        style: StrokeStyle(lineWidth: 0.7, dash: [2, 4])
                    )
                    .frame(width: 72, height: 72)
            }
            FloatingGlyph(
                text: ch.glyph,
                iconData: ch.iconData,
                phase: idx,
                fontSize: fontSize,
                paused: isFocused                // freeze float when focused
            )
        }
        .scaleEffect(scale)
        .opacity(isOtherFocused ? 0 : 1)
        .position(pos)
        .animation(.spring(response: 0.54, dampingFraction: 0.78), value: focusedID)
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: gravityID)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard focusedID == nil else { return }
                    if abs(value.translation.width) + abs(value.translation.height) > 6 {
                        cancelPress()
                        gravityID = nil
                        let newX = min(max(28, value.location.x), w - 28) / w
                        let newY = min(max(28, value.location.y), h - 28) / h
                        normPositions[ch.id] = CGPoint(x: newX, y: newY)
                    } else {
                        startLongPress(for: ch.id)
                    }
                }
                .onEnded { value in
                    cancelPress()
                    let tiny = abs(value.translation.width) + abs(value.translation.height) < 6
                    if tiny {
                        toggleFocus(ch.id)
                    }
                    gravityID = nil
                }
        )
        .allowsHitTesting(!isOtherFocused)
    }

    private func toggleFocus(_ id: UUID) {
        withAnimation(.spring(response: 0.54, dampingFraction: 0.78)) {
            focusedID = (focusedID == id) ? nil : id
        }
    }

    // ─── Focused detail panel ─────────────────────────────────────
    @ViewBuilder
    private func focusedPanel(chapter ch: Chapter, w: CGFloat, h: CGFloat) -> some View {
        // The glyph itself is rendered by the regular glyphNode loop. This
        // panel contains everything else that orbits the drop-cap.
        ZStack(alignment: .topLeading) {
            // × close (top-right of card)
            Button {
                toggleFocus(ch.id)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                        .background(Circle().fill(Theme.Palette.card))
                        .frame(width: 26, height: 26)
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            .position(x: w - 26, y: 24)
            .panelStagger(delay: 0.20)

            // TYPE meta (above title, right of cap)
            Text(ch.type.label)
                .font(Theme.Font.mono(9.5, weight: .medium))
                .tracking(2.2)
                .foregroundStyle(Theme.Palette.inkFaint)
                .position(x: 144 + 60, y: 26)
                .frame(width: 120, alignment: .leading)
                .panelStagger(delay: 0.24)

            // Title (italic serif, right of cap)
            Text(ch.title)
                .font(Theme.Font.serifItalic(24))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(2)
                .frame(width: 188, alignment: .leading)
                .position(x: 144 + 188/2, y: 32 + 40)
                .panelStagger(delay: 0.28)

            // State pill + range row
            HStack(spacing: 8) {
                StatePill(status: ch.status)
                Text(ch.rangeShort)
                    .font(Theme.Font.mono(9.5))
                    .tracking(0.6)
                    .foregroundStyle(Theme.Palette.inkFainter)
            }
            .position(x: 144 + 90, y: 130)
            .panelStagger(delay: 0.32)

            // Purpose paragraph
            if let purpose = ch.purpose, !purpose.isEmpty {
                Text(purpose)
                    .font(Theme.Font.serif(16))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)
                    .frame(width: w - 44, alignment: .leading)
                    .position(x: w / 2, y: 192 + 34)
                    .panelStagger(delay: 0.36)
            }

            // PROGRESS row
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("PROGRESS")
                        .font(Theme.Font.mono(9.5))
                        .tracking(1.6)
                        .foregroundStyle(Theme.Palette.inkFaint)
                    Spacer()
                    Text("\(ch.doneTodos.count) of \(ch.todos.count)")
                        .font(Theme.Font.mono(10.5))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                HairlineProgress(
                    done: ch.doneTodos.count,
                    total: ch.todos.count,
                    accent: ch.accent
                )
            }
            .frame(width: w - 44)
            .position(x: w / 2, y: 306)
            .panelStagger(delay: 0.40)

            // TODO preview (up to 3)
            let preview = openTodosFor(ch).prefix(3)
            VStack(alignment: .leading, spacing: 6) {
                if preview.isEmpty {
                    Text("No open todos.")
                        .font(Theme.Font.serifItalic(13.5))
                        .foregroundStyle(Theme.Palette.inkFaint)
                } else {
                    ForEach(Array(preview), id: \.id) { t in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(t.isOverdue ? Theme.Palette.teal : Theme.Palette.forest)
                                .frame(width: 5, height: 5)
                            Text(t.text)
                                .font(Theme.Font.sans(13))
                                .foregroundStyle(Theme.Palette.inkSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            if let due = t.dueDate {
                                Text(shortDueLabel(due))
                                    .font(Theme.Font.mono(9))
                                    .foregroundStyle(t.isOverdue ? Theme.Palette.teal : Theme.Palette.inkFainter)
                            }
                        }
                    }
                }
            }
            .frame(width: w - 44, alignment: .leading)
            .position(x: w / 2, y: 360)
            .panelStagger(delay: 0.44)

            // Open chapter button
            Button {
                onOpen(ch)
            } label: {
                HStack {
                    Text("Open chapter")
                        .font(Theme.Font.sans(13, weight: .medium))
                        .tracking(0.4)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(width: w - 44)
                .background(Theme.Palette.ink)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .position(x: w / 2, y: h - 30)
            .panelStagger(delay: 0.48)
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    private func openTodosFor(_ ch: Chapter) -> [Todo] {
        ch.todos
            .filter { !$0.done }
            .sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (l?, r?): return l < r
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.createdAt < b.createdAt
                }
            }
    }

    private func shortDueLabel(_ d: Date) -> String {
        // Reuse the cached "MMM d" static rather than building one per render.
        AtlasFormat.shortDay.string(from: d)
    }

    // ─── Long-press / gravity ─────────────────────────────────────
    private func startLongPress(for id: UUID) {
        guard longPressTimer == nil else { return }
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { _ in
            withAnimation { gravityID = id }
        }
    }
    private func cancelPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    private func edgeColor(_ edge: ChapterLink) -> Color {
        switch edge.relation {
        case .enables:            return Theme.Palette.forest
        case .blocks, .conflicts:  return Theme.Palette.teal
        case .related:            return Theme.Palette.inkFaint
        }
    }
    private func magnitudeFor(_ r: LinkRelation) -> CGFloat {
        switch r {
        case .blocks:    return 0.25
        case .conflicts: return 0.22
        default:         return 0.18
        }
    }
}

// ─── Floating glyph with optional pause + custom font size ──────────
struct FloatingGlyph: View {
    let text: String
    var iconData: Data? = nil
    let phase: Int
    var fontSize: CGFloat = 56
    var paused: Bool = false

    /// Resolved once per `iconData` change — NOT decoded/cropped every frame.
    /// The crop is a full-image pixel scan; doing it inside the 30fps timeline
    /// body was the H5 hot path. Off-main so the launch/scroll frames stay free.
    @State private var cropped: UIImage?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30, paused: paused)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let cycle = 6.0 + Double(phase % 4) * 1.4
            let p = paused ? 0 : sin((t + Double(phase) * 0.7) * (2 * .pi / cycle))
            let q = paused ? 0 : cos((t + Double(phase) * 0.7) * (2 * .pi / cycle))
            let offset: CGSize = {
                switch phase % 4 {
                case 0: return CGSize(width: 3 * p, height: -2 * p)
                case 1: return CGSize(width: -2 * p, height: 3 * p)
                case 2: return CGSize(width: 2 * q, height: 2 * p)
                default: return CGSize(width: -3 * p, height: -2 * q)
                }
            }()

            Group {
                if let img = cropped {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: fontSize * 1.4, height: fontSize * 1.4)
                } else {
                    Text(text)
                        .font(Theme.Font.serifItalic(fontSize))
                        .foregroundStyle(Theme.Palette.ink)
                        .kerning(fontSize > 80 ? -fontSize * 0.03 : 0)
                }
            }
            .offset(offset)
            .animation(.spring(response: 0.54, dampingFraction: 0.78), value: fontSize)
        }
        .task(id: iconData) {
            guard let data = iconData else { cropped = nil; return }
            // Decode + pixel-scan crop on a background executor; only the
            // resulting UIImage hops back to the main actor.
            cropped = await Task.detached(priority: .utility) {
                IconCropping.cropped(data)
            }.value
        }
    }
}

// ─── Curved label along a quadratic bezier ──────────────────────────
struct CurvedLabel: View {
    let text: String
    let start: CGPoint
    let end: CGPoint
    let control: CGPoint
    let color: Color
    var size: CGFloat = 11

    var body: some View {
        let chars = Array(text)
        guard !chars.isEmpty else { return AnyView(EmptyView()) }
        let n = chars.count
        let samples = 24
        var pts: [CGPoint] = []
        var lens: [CGFloat] = [0]
        var prev = bezier(0)
        for i in 1...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let p = bezier(t)
            pts.append(p)
            lens.append(lens.last! + hypot(p.x - prev.x, p.y - prev.y))
            prev = p
        }
        let totalLen = lens.last ?? 1
        let usedFrac: CGFloat = 0.6
        let pad = (1 - usedFrac) / 2
        let startLen = totalLen * pad
        let endLen = totalLen * (1 - pad)
        let spanLen = endLen - startLen

        return AnyView(
            ZStack {
                ForEach(0..<n, id: \.self) { i in
                    let frac = CGFloat(i + 1) / CGFloat(n + 1)
                    let target = startLen + frac * spanLen
                    let t = arcLengthToT(target, lens: lens, samples: samples)
                    let p = bezier(t)
                    let tan = tangent(t)
                    let angle = atan2(tan.dy, tan.dx)
                    let nx = -sin(angle), ny = cos(angle)
                    let base = CGPoint(x: p.x - nx * 7, y: p.y - ny * 7)
                    Text(String(chars[i]))
                        .font(Theme.Font.serifItalic(size))
                        .foregroundStyle(color)
                        .rotationEffect(.radians(Double(angle)))
                        .position(base)
                }
            }
        )
    }

    private func bezier(_ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt*mt*start.x + 2*mt*t*control.x + t*t*end.x,
            y: mt*mt*start.y + 2*mt*t*control.y + t*t*end.y
        )
    }
    private func tangent(_ t: CGFloat) -> CGVector {
        let mt = 1 - t
        return CGVector(
            dx: 2*mt*(control.x - start.x) + 2*t*(end.x - control.x),
            dy: 2*mt*(control.y - start.y) + 2*t*(end.y - control.y)
        )
    }
    private func arcLengthToT(_ target: CGFloat, lens: [CGFloat], samples: Int) -> CGFloat {
        for i in 1..<lens.count {
            if lens[i] >= target {
                let l0 = lens[i - 1], l1 = lens[i]
                let frac = l1 == l0 ? 0 : (target - l0) / (l1 - l0)
                let t0 = CGFloat(i - 1) / CGFloat(samples)
                let t1 = CGFloat(i) / CGFloat(samples)
                return t0 + (t1 - t0) * frac
            }
        }
        return 1
    }
}

// ─── Panel stagger reveal modifier ──────────────────────────────────
private struct PanelStagger: ViewModifier {
    let delay: Double
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .blur(radius: visible ? 0 : 3)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(delay)) {
                    visible = true
                }
            }
    }
}

private extension View {
    func panelStagger(delay: Double) -> some View {
        modifier(PanelStagger(delay: delay))
    }
}
