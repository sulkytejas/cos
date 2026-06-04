import SwiftUI
import SwiftData

/// Chapters — the constellation map of the user's life-threads. Positioned
/// nodes on water connected by curved edges, with a frosted detail strip that
/// updates as you tap a node (plus a brief Halo re-orient flicker).
struct ChaptersScreen: View {
    @Environment(HaloController.self) private var halo
    @Environment(\.modelContext) private var context
    /// Opens a chapter's Living Chapter detail in-shell (v0.7). Wired by AyumiRoot.
    @Environment(\.openLivingChapter) private var openLivingChapter

    // Live data. Chapters drive nodes, ChapterLinks drive edges, active
    // Watchers drive the live-pulse + watcher counts. All filtering that
    // touches enums goes through the raw stored columns / in-memory passes.
    @Query(sort: \Chapter.createdAt) private var chapterRows: [Chapter]
    @Query private var linkRows: [ChapterLink]
    @Query(filter: #Predicate<Watcher> { $0.statusRaw == "active" },
           sort: \Watcher.createdAt) private var activeWatchers: [Watcher]
    @Query private var briefRows: [Brief]

    @State private var selected: String = "strat"
    @State private var pressed: String? = nil
    @State private var flickerWork: DispatchWorkItem?
    @State private var didInitSelection = false

    private struct Node: Identifiable {
        let id: String; let glyph: String; let x: CGFloat; let y: CGFloat
        let size: CGFloat; let pulse: Bool; let delay: Double
    }
    private let seedNodes: [Node] = [
        .init(id: "strat", glyph: "S", x: 90, y: 90, size: 54, pulse: true, delay: 0),
        .init(id: "ireland", glyph: "I", x: 220, y: 100, size: 46, pulse: true, delay: 0.5),
        .init(id: "portrait", glyph: "V", x: 280, y: 220, size: 40, pulse: false, delay: 0),
        .init(id: "health", glyph: "H", x: 120, y: 250, size: 44, pulse: true, delay: 0.9),
    ]

    /// The North India node (README §"Reaching the chapter", data-ch="north"):
    /// the v0.7 Living Chapter — live, mid-trip, so it pulses. Always present in
    /// the constellation (it is intentionally never DB-backed), and selecting it
    /// surfaces the "Open this chapter →" link into LivingChapterView.
    private let northNode = Node(id: "north", glyph: "N", x: 206, y: 248,
                                 size: 50, pulse: true, delay: 0.3)

    // Deterministic node positions in the 350×340 space, cycling the seeded
    // anchors by index so the layout stays stable across launches without
    // adding a schema field.
    private static let positionAnchors: [(x: CGFloat, y: CGFloat)] = [
        (90, 90), (220, 100), (280, 220), (120, 250),
    ]

    // ─── Live → view models ───────────────────────────────────────
    private var nodes: [Node] {
        // North India is always in the sky (the v0.7 Living Chapter).
        guard !chapterRows.isEmpty else { return seedNodes + [northNode] }
        let watcherChapterIDs = Set(activeWatchers.compactMap { $0.chapter?.id })
        let sizes: [CGFloat] = [54, 46, 40, 44]
        let delays: [Double] = [0, 0.5, 0, 0.9]
        let live = chapterRows.enumerated().map { i, chapter -> Node in
            let anchor = Self.positionAnchors[i % Self.positionAnchors.count]
            // Spread successive cycles slightly so overlapping anchors fan out.
            let cycle = CGFloat(i / Self.positionAnchors.count)
            let x = min(max(anchor.x + cycle * 18, 30), 320)
            let y = min(max(anchor.y + cycle * 14, 30), 310)
            let isActive = chapter.status == .active
            return Node(
                id: chapter.id.uuidString,
                glyph: chapter.glyph,
                x: x,
                y: y,
                size: isActive ? sizes[i % sizes.count] : max(sizes[i % sizes.count] - 6, 38),
                pulse: isActive && watcherChapterIDs.contains(chapter.id),
                delay: delays[i % delays.count]
            )
        }
        return live + [northNode]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                // Head (`.head`, padding:6px 24px 0) — inset 24 like the prototype.
                Group {
                    Text(threadHeader)
                        .font(Theme.Font.mono(9.5)).tracking(1.7).foregroundStyle(Theme.Palette.ink3)
                        .padding(.bottom, 6)
                    Text("Your constellation.")
                        .font(Theme.Font.serifItalic(34)).foregroundStyle(Theme.Palette.ink)
                }
                .padding(.horizontal, 24)

                // The constellation (`.constellation`, width:100%, height:340) is
                // FULL-BLEED in the prototype — it breaks out of the head's 24px
                // inset so S/V sit near the page edges. Node coords live in a
                // 350×340 space mapped to the full body width.
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let sx = { (v: CGFloat) in v / 350 * w }
                    let sy = { (v: CGFloat) in v / 340 * h }
                    ZStack {
                        edges(sx: sx, sy: sy)
                        ForEach(nodes) { node in
                            nodeView(node)
                                .position(x: sx(node.x), y: sy(node.y))
                        }
                    }
                }
                .frame(height: 340)
                .padding(.top, 8)

                Spacer()
            }
            .padding(.top, 70)

            detailStrip
        }
        .onAppear {
            guard !didInitSelection else { return }
            if let first = chapterRows.first { selected = first.id.uuidString }
            didInitSelection = true
        }
    }

    // Header copy: live counts when chapters exist, else the seeded line.
    private var threadHeader: String {
        guard !chapterRows.isEmpty else { return "6 THREADS · 4 ACTIVE" }
        let active = chapterRows.filter { $0.status == .active }.count
        return "\(chapterRows.count) THREADS · \(active) ACTIVE"
    }

    private func edges(sx: @escaping (CGFloat) -> CGFloat, sy: @escaping (CGFloat) -> CGFloat) -> some View {
        ZStack {
            if chapterRows.isEmpty || liveEdges.isEmpty {
                // The exact four edges from the prototype constellation. North
                // India sits ON the Health→Portrait curve (M120,250 Q200,270
                // 280,220), so it needs no edge of its own — the H→V curve runs
                // straight through the N node.
                edge(90, 90, 150, 130, 220, 100, sx, sy, Theme.Palette.teal, 0.35, nil)
                edge(220, 100, 250, 170, 280, 220, sx, sy, Theme.Palette.forest, 0.30, nil)
                edge(90, 90, 70, 180, 120, 250, sx, sy, Theme.Palette.teal, 0.30, [3, 4])
                edge(120, 250, 200, 270, 280, 220, sx, sy, Theme.Palette.teal, 0.32, nil)
            } else {
                ForEach(liveEdges) { e in
                    edge(e.x0, e.y0, (e.x0 + e.x1) / 2, (e.y0 + e.y1) / 2 - 30, e.x1, e.y1,
                         sx, sy, e.color, e.opacity, e.dash)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private struct LiveEdge: Identifiable {
        let id: String
        let x0: CGFloat; let y0: CGFloat; let x1: CGFloat; let y1: CGFloat
        let color: Color; let opacity: Double; let dash: [CGFloat]?
    }

    // Edges derived from ChapterLink: from/to chapter ids → live node positions.
    // Color/dash from the relation; enables→forest, blocks/conflicts→teal dashed,
    // related→teal.
    private var liveEdges: [LiveEdge] {
        guard !chapterRows.isEmpty else { return [] }
        let pos: [UUID: (x: CGFloat, y: CGFloat)] = {
            var m: [UUID: (CGFloat, CGFloat)] = [:]
            for (i, chapter) in chapterRows.enumerated() {
                let anchor = Self.positionAnchors[i % Self.positionAnchors.count]
                let cycle = CGFloat(i / Self.positionAnchors.count)
                m[chapter.id] = (min(max(anchor.x + cycle * 18, 30), 320),
                                 min(max(anchor.y + cycle * 14, 30), 310))
            }
            return m
        }()
        return linkRows.compactMap { link in
            guard let from = link.fromChapter?.id, let to = link.toChapter?.id,
                  let p0 = pos[from], let p1 = pos[to] else { return nil }
            let color: Color
            let opacity: Double
            let dash: [CGFloat]?
            switch link.relation {
            case .enables:
                color = Theme.Palette.forest; opacity = 0.30; dash = nil
            case .blocks, .conflicts:
                color = Theme.Palette.teal; opacity = 0.30; dash = [3, 4]
            case .related:
                color = Theme.Palette.teal; opacity = 0.35; dash = nil
            }
            return LiveEdge(id: link.id.uuidString, x0: p0.x, y0: p0.y, x1: p1.x, y1: p1.y,
                            color: color, opacity: opacity, dash: dash)
        }
    }

    private func edge(_ x0: CGFloat, _ y0: CGFloat, _ cx: CGFloat, _ cy: CGFloat, _ x1: CGFloat, _ y1: CGFloat,
                      _ sx: (CGFloat) -> CGFloat, _ sy: (CGFloat) -> CGFloat,
                      _ color: Color, _ opacity: Double, _ dash: [CGFloat]?) -> some View {
        Path { p in
            p.move(to: CGPoint(x: sx(x0), y: sy(y0)))
            p.addQuadCurve(to: CGPoint(x: sx(x1), y: sy(y1)), control: CGPoint(x: sx(cx), y: sy(cy)))
        }
        .stroke(color.opacity(opacity), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: dash ?? []))
    }

    private func nodeView(_ node: Node) -> some View {
        let active = selected == node.id
        return VStack(spacing: 6) {
            Circle()
                .fill(active ? AnyShapeStyle(Theme.Palette.obsidian) : AnyShapeStyle(Theme.Palette.card))
                .frame(width: node.size, height: node.size)
                .overlay(active
                    ? AnyView(Circle().fill(RadialGradient(colors: [Theme.Palette.pulseTeal.opacity(0.4), .clear],
                                                           center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: node.size * 0.6)))
                    : AnyView(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1)))
                .overlay(Text(node.glyph).font(Theme.Font.serifItalic(18))
                    .foregroundStyle(active ? Theme.Palette.avatarInk : Theme.Palette.ink))
                .overlay(alignment: .topTrailing) {
                    if node.pulse { LivePulseDot().offset(x: 3, y: -3) }
                }
                .shadow1()
                .scaleEffect(pressed == node.id ? 1.08 : 1)
            Text(label(node.id))
                .font(Theme.Font.serifItalic(13)).foregroundStyle(Theme.Palette.ink2).lineLimit(1).fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture { tap(node.id) }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) { pressed = node.id } }
            .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) { pressed = nil } })
    }

    private func tap(_ id: String) {
        withAnimation(Theme.Motion.overshoot(0.36)) { selected = id }
        halo.setState(.thinking)
        flickerWork?.cancel()
        let work = DispatchWorkItem { halo.setState(.idle) }
        flickerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    // ─── Detail strip ─────────────────────────────────────────────
    private var detailStrip: some View {
        let d = detail(selected)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(d.active ? Theme.Palette.teal : Theme.Palette.ink4).frame(width: 6, height: 6)
                Text(d.status.uppercased()).font(Theme.Font.mono(9)).tracking(1.6).foregroundStyle(Theme.Palette.ink3)
            }
            .padding(.bottom, 6)
            Text(d.title).font(Theme.Font.serifItalic(28)).foregroundStyle(Theme.Palette.ink).padding(.bottom, 4)
            Text(d.desc).font(Theme.Font.serif(14.5)).foregroundStyle(Theme.Palette.ink2).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                ForEach(Array(d.stats.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.0).font(Theme.Font.serifItalic(18)).foregroundStyle(Theme.Palette.ink)
                        // Prototype `.stat` has no text-transform — labels stay
                        // lowercase (notes / watchers / last brief).
                        Text(s.1).font(Theme.Font.mono(9.5)).tracking(0.4).foregroundStyle(Theme.Palette.ink3)
                    }
                }
            }
            .padding(.top, 12)
            // A chapter with a Living Chapter detail (North India) gets a real
            // "Open this chapter →" link into LivingChapterView; the rest keep
            // the brief affordance.
            if let chapterId = d.livingChapterId {
                Button { openLivingChapter(chapterId) } label: {
                    Text("OPEN THIS CHAPTER →").font(Theme.Font.mono(10)).tracking(1.2)
                        .foregroundStyle(Theme.Palette.tealDeep)
                        .padding(.top, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if d.open {
                Text("OPEN LATEST BRIEF →").font(Theme.Font.mono(10)).tracking(1.2).foregroundStyle(Theme.Palette.tealDeep)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.init(top: 18, leading: 24, bottom: 30, trailing: 24))
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.white.opacity(0.7))
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.Palette.hairline).frame(height: 1) }
        .animation(Theme.Motion.overshoot(0.36), value: selected)
    }

    // ─── Data ─────────────────────────────────────────────────────
    private func chapter(for id: String) -> Chapter? {
        chapterRows.first { $0.id.uuidString == id }
    }

    private func label(_ id: String) -> String {
        if id == "north" { return "North India" }   // the v0.7 chapter, never DB-backed
        if let c = chapter(for: id) { return Self.shortLabel(c.title) }
        return ["strat": "Stratyfix", "ireland": "Ireland MBA", "portrait": "Portrait", "health": "Health"][id] ?? id
    }

    /// Node `.lbl` text. The prototype labels nodes with a short thread name
    /// ("Stratyfix", "Ireland MBA") while the detail strip carries the full
    /// title ("Stratyfix seed round"). Full DB titles overflow and overlap the
    /// neighbouring node, so collapse to the first ~two leading words, dropping
    /// trailing lowercase connectives (seed / relocation / baseline / valley…).
    private static func shortLabel(_ title: String) -> String {
        let words = title.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return title }
        var kept: [String] = []
        for w in words {
            // Keep up to two leading Capitalised / acronym words; stop at the
            // first lowercase descriptor ("seed", "relocation", "baseline").
            if let f = w.first, f.isUppercase {
                kept.append(w)
                if kept.count == 2 { break }
            } else {
                break
            }
        }
        if kept.isEmpty { kept = [words[0]] }
        // Drop a dangling connective ("Varanasi +" → "Varanasi").
        if let last = kept.last, last.allSatisfy({ !$0.isLetter }) { kept.removeLast() }
        return kept.joined(separator: " ")
    }
    private struct Detail {
        let status: String; let title: String; let desc: String
        let stats: [(String, String)]; let open: Bool; let active: Bool
        /// Non-nil ⇒ show "Open this chapter →" routing into LivingChapterView.
        var livingChapterId: String? = nil
    }
    private func detail(_ id: String) -> Detail {
        // The North India chapter is the v0.7 Living Chapter — never DB-backed,
        // and it carries the "Open this chapter →" link into LivingChapterView.
        if id == "north" {
            return .init(
                status: "Active · day 5 · in Rishikesh",
                title: "North India",
                desc: "Built from one flight email. I inferred a 12-day route, Delhi in to Chandigarh out, and I'm watching 4 sources as you go.",
                stats: [("₹34.7k", "spent"), ("2/5", "stops"), ("4", "sources")],
                open: true, active: true, livingChapterId: "north"
            )
        }

        // Live chapter selected → drive the strip from the model.
        if let c = chapter(for: id) {
            let isActive = c.status == .active
            let watchers = activeWatchers.filter { $0.chapter?.id == c.id }
            let hasBrief = briefRows.contains { $0.chapter?.id == c.id }
            let status = isActive
                ? (watchers.isEmpty ? "Active" : "Active · Ayumi watching")
                : c.status.label
            let cadence = watchers.first?.cadenceLabel ?? c.rangeShort
            return .init(
                status: status,
                title: c.title,
                desc: c.purpose ?? "",
                stats: [
                    ("\(c.entries.count)", "notes"),
                    ("\(watchers.count)", watchers.count == 1 ? "watcher" : "watchers"),
                    (cadence, watchers.isEmpty ? "next" : "cadence"),
                ],
                open: hasBrief || isActive,
                active: isActive
            )
        }

        // Empty-DB fallback → the original canned content, unchanged.
        switch id {
        case "ireland": return .init(status: "Active · Ayumi watching", title: "Ireland MBA relocation",
            desc: "VFS slots before Jun 28. Ayumi checks every 3 hours; nothing open yet.",
            stats: [("9", "notes"), ("1", "watcher"), ("3h", "cadence")], open: false, active: true)
        case "portrait": return .init(status: "Quiet · no watchers", title: "Portrait sitting",
            desc: "Sitting for V. tomorrow 11:00. Studio moved one block south.",
            stats: [("3", "notes"), ("0", "watchers"), ("Thu", "next")], open: true, active: false)
        case "health": return .init(status: "Active · Ayumi watching", title: "Health & relationships",
            desc: "Smruti's birthday in 11 days. A few standing reminders Ayumi keeps warm.",
            stats: [("6", "notes"), ("1", "watcher"), ("daily", "cadence")], open: false, active: true)
        default: return .init(status: "Active · Ayumi watching", title: "Stratyfix seed round",
            desc: "Karan at 14:30 today. Six notes this month; the open question is month-6 retention.",
            stats: [("14", "notes"), ("2", "watchers"), ("06:40", "last brief")], open: true, active: true)
        }
    }
}

/// Breathing teal pulse dot with a paper ring — shared live indicator.
struct LivePulseDot: View {
    var size: CGFloat = 8
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle()
            .fill(Theme.Palette.teal)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Theme.Palette.paper, lineWidth: 3))
            .opacity(on ? 1 : 0.4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
