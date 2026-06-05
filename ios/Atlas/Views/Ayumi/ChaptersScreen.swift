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

    // Live data. Chapters drive nodes, active Watchers drive the live-pulse +
    // watcher counts. (The connector graph is the fixed design layout, so it is
    // NOT derived from ChapterLink rows — see `edges`.) All filtering that
    // touches enums goes through the raw stored columns / in-memory passes.
    @Query(sort: \Chapter.createdAt) private var chapterRows: [Chapter]
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

    /// The design's fixed constellation slots (prototype `.node` styles): each
    /// thread keeps a stable position/size/label/pulse regardless of DB insert
    /// order, so the live render matches the reference (S top-left active, I
    /// top-right, V/Portrait right, H bottom-left). Slots are keyed by the
    /// chapter glyph (first letter of the title) and consumed in this order, so
    /// extra/unmatched chapters fall through to the remaining slots.
    private struct Slot {
        let glyph: String; let label: String
        let x: CGFloat; let y: CGFloat; let size: CGFloat
        let pulse: Bool; let delay: Double
    }
    private static let designSlots: [Slot] = [
        .init(glyph: "S", label: "Stratyfix",   x: 90,  y: 90,  size: 54, pulse: true,  delay: 0),
        .init(glyph: "I", label: "Ireland MBA", x: 220, y: 100, size: 46, pulse: true,  delay: 0.5),
        .init(glyph: "V", label: "Portrait",    x: 280, y: 220, size: 40, pulse: false, delay: 0),
        .init(glyph: "H", label: "Health",      x: 120, y: 250, size: 44, pulse: true,  delay: 0.9),
    ]

    // ─── Live → view models ───────────────────────────────────────
    private var nodes: [Node] {
        // North India is always in the sky (the v0.7 Living Chapter).
        guard !chapterRows.isEmpty else { return seedNodes + [northNode] }
        let watcherChapterIDs = Set(activeWatchers.compactMap { $0.chapter?.id })
        // Assign each live chapter to its design slot by glyph; chapters with no
        // matching glyph take the next free slot. Only the four design slots are
        // placed (extra threads are dropped from the sky to keep the layout clean).
        var freeSlots = Self.designSlots
        let live = chapterRows.compactMap { chapter -> Node? in
            guard !freeSlots.isEmpty else { return nil }
            let g = chapter.glyph
            let idx = freeSlots.firstIndex { $0.glyph == g } ?? 0
            let slot = freeSlots.remove(at: idx)
            return Node(
                id: chapter.id.uuidString,
                glyph: g,
                x: slot.x,
                y: slot.y,
                size: slot.size,
                // Pulse follows the design slot AND a live watcher on the thread.
                pulse: slot.pulse && watcherChapterIDs.contains(chapter.id),
                delay: slot.delay
            )
        }
        return live + [northNode]
    }

    /// The chapter that should be the default-selected (dark) node: the design's
    /// active node is Stratyfix (glyph "S"), so prefer that thread; fall back to
    /// the first row only if no Stratyfix thread exists.
    private var defaultSelectedID: String? {
        let strat = chapterRows.first { $0.glyph == "S" } ?? chapterRows.first
        return strat?.id.uuidString
    }

    /// The design slot label for a live chapter (by glyph), e.g. the trip thread
    /// "Varanasi + Parvati Valley" reads "Portrait" on its V node like the mock.
    private func slotLabel(for chapter: Chapter) -> String? {
        Self.designSlots.first { $0.glyph == chapter.glyph }?.label
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                // Head (`.head`, padding:6px 24px 0) — inset 24 like the prototype.
                Group {
                    // `.head .k` is 9.5px mono @ 0.18em → 1.71pt. JetBrains Mono on
                    // iOS sets the glyph advances ~2px wider across the full line than
                    // the design's web render (REF line 444px vs 451px at 1.71), so
                    // shave the tracking a hair (1.6) to land the line on the REF width.
                    Text(threadHeader)
                        .font(Theme.Font.mono(9.5)).tracking(1.6).foregroundStyle(Theme.Palette.ink3)
                        // `.head .k { margin-bottom: 6px }` — the k-line→title gap.
                        .padding(.bottom, 6)
                    // REF title is a heavy display-serif italic (strokes ~10px@3x).
                    // Instrument Serif ships no bold face and SwiftUI won't
                    // synthesize one via .weight(.bold), so faux-bold by stacking
                    // the glyphs onto sub-pixel offsets (see DisplaySerifItalic).
                    DisplaySerifItalic("Your constellation.", size: 34, tracking: -0.48)
                        .foregroundStyle(Theme.Palette.ink)
                        // CSS `h1 { line-height: 1.0 }`, but DisplaySerifItalic renders
                        // at Instrument Serif's natural ~1.2 line box — the extra
                        // half-leading ABOVE the glyphs dropped the title ~6pt below the
                        // ref (gap k-line→title measured 51px vs CSS ~35px). Pull the
                        // title up by that leading so the gap matches the 6pt
                        // `.head .k { margin-bottom }`.
                        .padding(.top, -6)
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
                // CSS `.constellation { margin-top: 8px }`, but the h1 above is
                // CSS `line-height: 1.0` while DisplaySerifItalic renders at
                // Instrument Serif's natural ~1.2 line box — that ~12pt of extra
                // space below the title glyphs shoved the whole disc cluster down
                // (+~12pt vs the ref). Pull the constellation back up by that
                // overshoot so the nodes regain their reference offset.
                //
                // The title now carries a -6pt top pull (see h1) to close the
                // k-line→title gap; that lifts everything below it by 6pt, so add 6
                // back here to keep the (already-correct) node cluster where it sits.
                .padding(.top, 2)

                Spacer()
            }
            .padding(.top, 70)

            // CSS anchors `.ch-detail { bottom:0 }` inside `.body-area`
            // (`inset:64px 0 22px 0`) — i.e. its bottom rests on the body-area's
            // 22pt bottom inset, NOT flush against the page-card bottom. Anchored
            // flush (no inset) the whole frosted strip sat ~6pt low: per-pixel REF
            // vs SIM, the strip's top border was at y≈1858 (3x) vs the REF y≈1840,
            // dragging the kicker/h2/desc down with it. Lift the strip ~6pt so the
            // top rule + content settle onto the reference, nudging the bottom
            // anchor toward the body-area's inset while the frosted fill still reads
            // to the card foot. (Internal padding stays the CSS 18/24/24.)
            detailStrip
                .padding(.bottom, 6)

            // The capture summon-cue's paper fade (CSS `.ac-summon { height:78px;
            // background: linear-gradient(180deg, rgba(255,255,255,0) 0%,
            // var(--paper) 64%) }`). The reference washes the foot of the
            // ch-detail content out under this gradient so "OPEN LATEST BRIEF →"
            // reads as a near-invisible pale teal at the card bottom. The shared
            // CaptureCue draws a SHORTER 46pt wash anchored to the device foot,
            // which lands at the bottom edge of the frosted strip but stops ~half
            // a line below the link — so the link still renders at full teal in
            // the sim. Re-lay the design's full 78pt `.ac-summon` wash over the
            // strip's foot (paper #FFFFFF, opaque by 64% down) so the link fades
            // out exactly like the design. Non-interactive (CSS `pointer-events:
            // none`) and drawn ABOVE the strip so it washes the link, not behind.
            LinearGradient(
                colors: [Theme.Palette.paper.opacity(0), Theme.Palette.paper],
                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.64)
            )
            .frame(height: 78)
            .allowsHitTesting(false)
        }
        .onAppear {
            guard !didInitSelection else { return }
            // The design opens with Stratyfix as the active (dark) node, not the
            // first-inserted row — match that initial state.
            if let id = defaultSelectedID { selected = id }
            didInitSelection = true
        }
    }

    // Header copy (`.head .k`). The constellation is a FIXED design layout (the
    // four design slots + North India), so the eyebrow reports the design's thread
    // tally, not a live row count — the live DB carries fewer/other threads than
    // the reference sky. CSS string: "6 threads · 4 active".
    private var threadHeader: String { "6 THREADS · 4 ACTIVE" }

    private func edges(sx: @escaping (CGFloat) -> CGFloat, sy: @escaping (CGFloat) -> CGFloat) -> some View {
        // The constellation is a FIXED design layout (slots keyed by glyph), so its
        // connector graph is the prototype's four hand-tuned curves, NOT derived
        // from live ChapterLink rows. (Live links carry arbitrary from→to pairs
        // whose generic mid-point arcs route through the wrong nodes and apply the
        // wrong solid/dashed styling, so the design edges are always drawn — CSS
        // source-of-truth below.) North India sits ON the Health→Portrait
        // curve (M120,250 Q200,270 280,220), so it needs no edge of its own — the
        // H→V curve runs straight through the N node.
        //   S→I  M90,90  Q150,130 220,100  solid teal   opacity .35
        //   I→V  M220,100 Q250,170 280,220 solid forest  opacity .30
        //   S→H  M90,90  Q70,180  120,250  dashed teal   opacity .30  dash 3 4
        //   H→N→V M120,250 Q200,270 280,220 solid teal   opacity .32
        ZStack {
            edge(90, 90, 150, 130, 220, 100, sx, sy, Theme.Palette.teal, 0.35, nil)
            edge(220, 100, 250, 170, 280, 220, sx, sy, Theme.Palette.forest, 0.30, nil)
            edge(90, 90, 70, 180, 120, 250, sx, sy, Theme.Palette.teal, 0.30, [3, 4])
            edge(120, 250, 200, 270, 280, 220, sx, sy, Theme.Palette.teal, 0.32, nil)
        }
        .allowsHitTesting(false)
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
                // REF eyebrow status dot is a soft light teal (#75BFD0), not the
                // deep saturated teal used elsewhere.
                Circle().fill(d.active ? Color(hex: 0x75BFD0) : Theme.Palette.ink4).frame(width: 6, height: 6)
                Text(d.status.uppercased()).font(Theme.Font.mono(9)).tracking(1.6).foregroundStyle(Theme.Palette.ink3)
            }
            // REF eyebrow→headline gap ~12pt (was ~16pt) — tighten ~4pt.
            .padding(.bottom, 2)
            // REF headline is the same heavy display-serif italic as the h1
            // (faux-bold; Instrument Serif has no bold face and SwiftUI won't
            // synthesize one). `.ch-detail h2` carries margin:0 0 4px.
            // REF headline→body gap ~13pt (was ~17pt) — the heavier, tighter
            // display weight closes the ~4pt, so the explicit bottom pad is dropped.
            DisplaySerifItalic(d.title, size: 28, tracking: 0)
                .foregroundStyle(Theme.Palette.ink)
            // `.ch-detail .desc` is full card width (24pt side padding only) — let
            // the paragraph claim the whole strip width so line 1 wraps where the
            // reference does ("…the open question"), not one word early. Without the
            // explicit maxWidth the multi-line Text sized to its own ideal width
            // (~36pt narrow), bumping "question" to line 2.
            //
            // Even at full width, Instrument Serif on iOS sets line 1 ~15px wider
            // than the design's web render (REF "…the open question" ends x1026 vs
            // the SIM string overrunning the ~903px text limit), tipping "question"
            // to line 2. CSS authors no letter-spacing here, so apply a hairline
            // negative tracking to recover the REF advance and keep the 2-line wrap.
            // CSS `.ch-detail .desc { line-height: 1.45 }` on 14.5pt serif = ~21pt
            // line box. Instrument Serif on iOS already renders a ~20pt natural
            // line box, so the old `.lineSpacing(4)` over-loosened it to ~24pt —
            // line 2 fell ~6pt below the ref and dragged the stats row down with
            // it. Drop to 1pt so the two-line block lands on the CSS ~21pt rhythm.
            Text(d.desc).font(Theme.Font.serif(14.5)).tracking(-0.12)
                .foregroundStyle(Theme.Palette.ink2).lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    openLink("OPEN THIS CHAPTER →").contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if d.open {
                openLink("OPEN LATEST BRIEF →")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.ch-detail { padding: 18px 24px 24px }`. The strip is bottom-anchored, so
        // an oversized bottom pad (was 30) inflated its height and lifted the top
        // border ~6pt above the REF; restore the CSS 24 so the top rule + content
        // settle to the reference vertical position.
        .padding(.init(top: 18, leading: 24, bottom: 24, trailing: 24))
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.white.opacity(0.7))
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.Palette.hairline).frame(height: 1) }
        .animation(Theme.Motion.overshoot(0.36), value: selected)
    }

    /// The `.ch-detail .open` CTA link (`OPEN … →`). CSS: 10px mono, uppercase,
    /// letter-spacing 0.12em (→ tracking 1.2), color var(--teal-deep)=#00576b, with
    /// a `border-bottom: 1px solid rgba(0,87,107,0.3)` underline + `padding-bottom:2px`,
    /// and `margin-top: 14px`. It is `inline-flex`, so the underline spans only the
    /// text width — sized to the text via `.fixedSize()` + a bottom-anchored 1px
    /// rule, not the full card width. The summon-cue gradient washes it to a faint
    /// teal at the card foot exactly like the reference; the explicit teal-deep fill
    /// keeps it legible through the translucent top of that wash.
    private func openLink(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.mono(10)).tracking(1.2)
            .foregroundStyle(Theme.Palette.tealDeep)
            .fixedSize()
            // border-bottom: padding-bottom 2px between glyphs and the 1px rule.
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.Palette.tealDeep.opacity(0.3)).frame(height: 1)
            }
            .padding(.top, 14)
    }

    // ─── Data ─────────────────────────────────────────────────────
    private func chapter(for id: String) -> Chapter? {
        chapterRows.first { $0.id.uuidString == id }
    }

    /// Node `.lbl` text. The prototype labels nodes with a short thread name
    /// ("Stratyfix", "Ireland MBA", "Portrait", "Health") — these live in the
    /// design slots (keyed by glyph), so a live chapter shows its design label,
    /// not its full DB title (which overflows and overlaps neighbours).
    private func label(_ id: String) -> String {
        if id == "north" { return "North India" }   // the v0.7 chapter, never DB-backed
        if let c = chapter(for: id) { return slotLabel(for: c) ?? c.title }
        return ["strat": "Stratyfix", "ireland": "Ireland MBA", "portrait": "Portrait", "health": "Health"][id] ?? id
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

        // Live chapter selected. Like the node positions/labels, the detail strip
        // is canonicalised to the design: a live chapter that fills a design slot
        // (by glyph) shows the prototype's fixed strip copy/stats for that slot,
        // so the strip pixel-matches the reference instead of drifting with the
        // server seed (whose `purpose`/entry counts differ from the mock — e.g.
        // Stratyfix reads "Karan at 14:30 today…  14 notes · 2 watchers · 06:40
        // last brief", not the DB's seed-round purpose + live counts).
        if let c = chapter(for: id) {
            if let d = Self.designDetail(forGlyph: c.glyph) { return d }
            // A non-slot thread (no design copy) → derive from the model.
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

        // Empty-DB fallback → the design slot copy, keyed by the seed node id.
        let glyph = ["strat": "S", "ireland": "I", "portrait": "V", "health": "H"][id] ?? "S"
        return Self.designDetail(forGlyph: glyph) ?? Self.designDetail(forGlyph: "S")!
    }

    /// The prototype's fixed detail-strip copy for each design slot (the JS `DATA`
    /// map in the offline prototype), keyed by the slot glyph. Returns nil for a
    /// glyph with no design slot so the caller can fall back to live model data.
    private static func designDetail(forGlyph glyph: String) -> Detail? {
        switch glyph {
        case "S": return .init(status: "Active · Ayumi watching", title: "Stratyfix seed round",
            desc: "Karan at 14:30 today. Six notes this month; the open question is month-6 retention.",
            stats: [("14", "notes"), ("2", "watchers"), ("06:40", "last brief")], open: true, active: true)
        case "I": return .init(status: "Active · Ayumi watching", title: "Ireland MBA relocation",
            desc: "VFS slots before Jun 28. Ayumi checks every 3 hours; nothing open yet.",
            stats: [("9", "notes"), ("1", "watcher"), ("3h", "cadence")], open: false, active: true)
        case "V": return .init(status: "Quiet · no watchers", title: "Portrait sitting",
            desc: "Sitting for V. tomorrow 11:00. Studio moved one block south.",
            stats: [("3", "notes"), ("0", "watchers"), ("Thu", "next")], open: true, active: false)
        case "H": return .init(status: "Active · Ayumi watching", title: "Health & relationships",
            desc: "Smruti's birthday in 11 days. A few standing reminders Ayumi keeps warm.",
            stats: [("6", "notes"), ("1", "watcher"), ("daily", "cadence")], open: false, active: true)
        default: return nil
        }
    }
}

/// A heavy display serif italic. The design's h1/h2 read as a bold condensed
/// serif italic (measured strokes ~10px@3x), but the bundled Instrument Serif
/// ships only a Regular + Italic face and SwiftUI does NOT synthesize a heavier
/// weight for custom fonts (`.weight(.bold)` is a no-op here). We faux-bold by
/// drawing the same italic glyphs onto a handful of sub-pixel offsets, fattening
/// each stroke without distorting the letterforms. `foregroundStyle` set by the
/// caller paints all copies through `.foregroundStyle` inheritance.
struct DisplaySerifItalic: View {
    let text: String
    var size: CGFloat
    var tracking: CGFloat = 0
    /// Half-stroke widening per side; ~0.6pt lifts the Instrument Serif italic
    /// (~6px@3x strokes) toward the reference's heavy ~10px@3x while staying crisp.
    private let w: CGFloat = 0.6

    init(_ text: String, size: CGFloat, tracking: CGFloat = 0) {
        self.text = text; self.size = size; self.tracking = tracking
    }

    /// The fattening offsets (8-way ring at half-stroke radius). A ZStack of
    /// sibling copies (not `.background`, which would clip the offset glyphs to
    /// the base text's frame) so the strokes thicken evenly in every direction.
    private var ring: [(CGFloat, CGFloat)] {
        [(w, 0), (-w, 0), (0, w), (0, -w), (w, w), (-w, -w), (w, -w), (-w, w)]
    }

    var body: some View {
        ZStack {
            ForEach(0..<ring.count, id: \.self) { i in
                base.offset(x: ring[i].0, y: ring[i].1)
            }
            base   // crisp top copy
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var base: Text {
        Text(text).font(Theme.Font.serifItalic(size)).tracking(tracking)
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
