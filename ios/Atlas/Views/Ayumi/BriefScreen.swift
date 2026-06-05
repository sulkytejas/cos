import SwiftUI
import SwiftData

/// Brief — the densest AI surface: Ayumi's pre-meeting brief on a person.
/// Framing → title → person → timeline (with citations) → tactical → predictions
/// → materials checklist → quote, over a sticky "Start the meeting" action bar.
struct BriefScreen: View {
    @Environment(HaloController.self) private var halo
    @Environment(\.modelContext) private var context
    @Environment(AtlasRepo.self) private var repo
    @Environment(NavRouter.self) private var router

    /// Most-recent surfaced Brief, if any. Empty → hardcoded fallback below.
    @Query(filter: #Predicate<Brief> { $0.statusRaw == "surfaced" },
           sort: \.surfaceAt, order: .reverse)
    private var surfacedBriefs: [Brief]

    @State private var ready: [String: Bool] = ["m1": true, "m2": true, "m3": false, "m4": false]
    @State private var receipt: Receipt? = nil
    @State private var rings: [EORingItem] = []
    @State private var started = false

    // ─── Live brief binding ───────────────────────────────────────
    /// The brief we drive sections from, or nil → fully hardcoded screen.
    ///
    /// This surface is the *person* brief (the reference is Karan's pre-meeting
    /// prep: person → timeline → tactical …). Several briefs can be `surfaced`
    /// at once (portrait sitting, trip approaching), and their `surfaceAt`
    /// ordering is not stable across a server sync — a plain `.first` can land
    /// on the trip brief, which has no person and a *trip-itinerary* timeline,
    /// so the screen would bind to the wrong dataset. Prefer the brief whose
    /// decoded structure carries a `.person` section; fall back to the newest
    /// surfaced one only if none does.
    private var liveBrief: Brief? {
        surfacedBriefs.first { Self.hasPerson($0) } ?? surfacedBriefs.first
    }

    /// True when a brief's encoded structure contains a `.person` section.
    private static func hasPerson(_ brief: Brief) -> Bool {
        guard let s = try? JSONDecoder().decode(BriefStructure.self, from: brief.structureData) else { return false }
        return s.sections.contains { if case .person = $0 { return true } else { return false } }
    }

    /// Decode structureData ONCE (same approach as BriefRenderer.structure).
    private var structure: BriefStructure? {
        guard let liveBrief else { return nil }
        return try? JSONDecoder().decode(BriefStructure.self, from: liveBrief.structureData)
    }

    // Per-kind section data, present only when the decoded brief carries it.
    private var personData: PersonData? {
        structure?.sections.compactMap { if case .person(let d) = $0 { return d } else { return nil } }.first
    }
    private var timelineData: TimelineData? {
        structure?.sections.compactMap { if case .timeline(let d) = $0 { return d } else { return nil } }.first
    }
    private var tacticalData: TacticalData? {
        structure?.sections.compactMap { if case .tactical(let d) = $0 { return d } else { return nil } }.first
    }
    private var predictionData: PredictionData? {
        structure?.sections.compactMap { if case .prediction(let d) = $0 { return d } else { return nil } }.first
    }
    private var materialsData: MaterialsData? {
        structure?.sections.compactMap { if case .materials(let d) = $0 { return d } else { return nil } }.first
    }
    private var quoteData: QuoteData? {
        structure?.sections.compactMap { if case .quote(let d) = $0 { return d } else { return nil } }.first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navBar
                        // Ref topbar→first-feed gap (Today glyph top → Ayumi row)
                        // is ~45pt; at .bottom 18 the sim landed ~9pt tight. The
                        // CSS `.conv` clears the topbar with more air than the bare
                        // 18pt here — open it to 27 so the Ayumi meta row drops to
                        // the reference y.
                        .padding(.bottom, 27)
                    framing
                    // The 46pt slot is a subject/name, not a sentence. Use the
                    // brief's person name when it carries one; otherwise this is
                    // the static demo, so show the demo subject (matches the mock)
                    // rather than a live digest title like "Handled while you slept."
                    Text((personData?.name).map { $0 + "." } ?? "Karan Mehta.")
                        .font(Theme.Font.serifItalic(46))
                        .foregroundStyle(Theme.Palette.ink)
                        .tracking(-0.9)
                        // CSS .brief-title { margin: 18px 0 2px; line-height: 0.98 }.
                        // Instrument Serif's SwiftUI line box adds ~11pt of leading
                        // below the glyphs at 46pt; pull the brief-sub up so it sits
                        // ~2pt under the title (mock gap ≈12pt, not the ~23pt the
                        // default line box yields). The same top leading also pushed
                        // the title (and everything below) ~3.3pt low vs the
                        // reference — the CSS 18px margin is measured from the tight
                        // line-height:0.98 box, so trim the SwiftUI top to 15 to
                        // reabsorb that cumulative drift (title/sub/person/history
                        // all ride back up to the design y).
                        .padding(.top, 15)
                        .padding(.bottom, -8)
                    HStack(spacing: 8) {
                        Text("today · 14:30").font(Theme.Font.mono(10)).tracking(0.4).foregroundStyle(Theme.Palette.tealDeep)
                        Rectangle().fill(Theme.Palette.rule).frame(width: 1, height: 9)
                        Text("Sequoia India · seed").font(Theme.Font.mono(10)).tracking(0.4).foregroundStyle(Theme.Palette.ink3)
                    }
                    // CSS .brief-title margin-bottom 2px → brief-sub sits ~2pt below.
                    .padding(.top, 2)

                    section("Person") { personBlock }
                    section("Your history with Karan") { timeline }
                    section("Ayumi suggests") { tactical }
                    section("Likely to come up") { predictions }
                    section("Have these open") { materials }
                    section("In his words") { quote }

                    Spacer().frame(height: 110)
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)            // CSS .conv padding-top 6
            }
            // The Today/STRATYFIX nav row replaces the shell app-mark on Brief
            // (the shell suppresses AppMark for .brief — see sharedRequests), so
            // content starts at the topbar band offset (CSS `.topbar{top:30px}`,
            // measured inside the page which is itself inset 22pt) rather than the
            // old 64px sentence inset. Pass-7: the ScrollView's own safe-area
            // content inset added ~4pt on top of this 30, landing the '‹ Today'
            // glyph at y63 vs the reference's y59 — pull this to 26 so the whole
            // header band + content column rides ~4pt higher to the design y.
            // The bottom stays open for the sticky action zone (the big in-content
            // spacer clears it).
            .padding(.top, 26)

            actionZone
            EOLayer(rings: rings)

            if let receipt {
                ReceiptSheetView(receipt: receipt) { withAnimation(Theme.Motion.standard(0.28)) { self.receipt = nil } }
                    .zIndex(30)
            }
        }
        .onAppear(perform: syncReadyFromMaterials)
    }

    // ─── Sections ─────────────────────────────────────────────────
    private func section<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(Theme.Font.mono(9)).tracking(2.0)
                .foregroundStyle(Theme.Palette.ink3)
                .padding(.bottom, 10)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
    }

    // ─── Header nav (replaces the shell app-mark on Brief) ────────
    /// Reference top chrome: a left `‹ Today` back-affordance (sans, dark ink)
    /// and a right `STRATYFIX ▾` trip/context label (mono, gray, tracked).
    private var navBar: some View {
        HStack(alignment: .center, spacing: 0) {
            Button { withAnimation(Theme.Motion.overshoot()) { router.go(.today) } } label: {
                // CSS `.back`: ink-2, sans 14px, gap 6px, thin chevron (svg stroke 1.4).
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .regular))
                    Text("Today").font(Theme.Font.sans(14))
                }
                .foregroundStyle(Theme.Palette.ink2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            // CSS `.crumb`: mono 9.5px, ink-3, letter-spacing 0.16em (≈1.5pt),
            // with a literal filled caret "▾" inline (not an SF chevron).
            Text("STRATYFIX ▾").font(Theme.Font.mono(9.5)).tracking(1.5)
                .foregroundStyle(Theme.Palette.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    private var framing: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Reference Ayumi avatar is a flat solid dark-green disc (no glossy
                // catchlight / teal pulse), unlike the shared `AyumiAvatar`. Render
                // the flat disc locally so the shared component (used glossy on
                // Today etc.) is left untouched.
                Circle().fill(Color(hex: 0x2E4A42)).frame(width: 18, height: 18)
                Text("Ayumi").font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("drafted 06:40 · 6 sources").font(Theme.Font.mono(9.5)).tracking(0.5).foregroundStyle(Theme.Palette.ink4)
            }
            // CSS `em.accent` is a teal highlighter *band* low over the glyphs
            // (`linear-gradient transparent 64% → rgba(0,137,168,0.16) 64%–92% →
            // transparent`), NOT a full-height block. AttributedString
            // `backgroundColor` would fill the whole em box (≈22pt at 21px → the
            // tall block the pass-4 diff flagged). Instead stack two identical
            // wrapping Texts: the BACK copy carries the teal band on "20 minutes"
            // and is masked to reveal only the lower 64–92% of each line, so the
            // band sits low and thin exactly where the run lands (wrapping stays
            // identical across both copies); the FRONT copy paints crisp glyphs
            // over it. The "20 minutes" run is roman (CSS `em.accent{font-style:
            // normal}`); the rest is serif italic, "Karan" roman.
            Text(briefProse(highlighted: true))
                .lineSpacing(1)                  // CSS line-height 1.34 × 21 ≈ 28pt pitch; Instrument Serif's natural line box already adds ~6pt leading, so lineSpacing(3) over-led to ~30pt — pull to 1 for a true 28pt pitch.
                .fixedSize(horizontal: false, vertical: true)
                .mask(highlightBandMask)
                .overlay(alignment: .topLeading) {
                    Text(briefProse(highlighted: false))
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
        }
    }

    /// A low repeating highlighter window: for each ~28pt line (text 21pt +
    /// lineSpacing 1 + ~6pt natural leading) reveal only the band sitting 64%→92%
    /// down the line box (≈8pt tall, straddling the baseline) — the highlighter
    /// read from the reference and the CSS gradient (transparent 64% → teal
    /// 64–92% → transparent), NOT the full-height block. Bands are laid out from
    /// the BOTTOM up so the last line (where "20 minutes" sits) keeps its band
    /// aligned to the baseline regardless of per-line advance rounding.
    private var highlightBandMask: some View {
        let line: CGFloat = 28                      // text 21 + lineSpacing 1 + leading
        let bandTop: CGFloat = line * 0.64          // CSS teal start (64% of line box) — sits low, near the baseline
        let bandH: CGFloat = line * 0.28            // CSS 64%→92% (≈8pt) — straddles the baseline
        return GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(0..<Int((geo.size.height / line).rounded(.up)) + 1, id: \.self) { _ in
                    VStack(spacing: 0) {
                        Color.clear.frame(height: bandTop)
                        Color.black.frame(height: bandH)
                        Color.clear.frame(height: line - bandTop - bandH)
                    }
                }
            }
        }
    }

    /// The framing paragraph. Built locally (not via `ayumiProse`). Italic serif
    /// voice; "Karan" and the accented "20 minutes" stay roman. When `highlighted`
    /// the "20 minutes" run carries the teal band fill (revealed low by the mask);
    /// the glyph copy passes `highlighted: false` so the band never tints text.
    private func briefProse(highlighted: Bool) -> AttributedString {
        let size: CGFloat = 21
        func run(_ s: String, italic: Bool = true) -> AttributedString {
            var a = AttributedString(s)
            a.font = .custom(italic ? Theme.Typeface.serifItalic : Theme.Typeface.serifRegular, size: size)
            // The band copy hides its glyphs (clear ink) so the low mask reveals
            // only the teal stripe — the visible glyphs come from the front copy.
            a.foregroundColor = highlighted ? Color.clear : Theme.Palette.ink
            return a
        }
        var highlight = run("20 minutes", italic: false)
        if highlighted { highlight.backgroundColor = Theme.Palette.teal.opacity(0.16) }
        return run("Here's what you need for ")
            + run("Karan", italic: false)
            + run(". He'll push on retention — I'd open with the cohort, not the round. He runs late, so plan for ")
            + highlight
            + run(", not 30.")
    }

    private var personBlock: some View {
        HStack(alignment: .top, spacing: 13) {
            AvatarObsidian(initials: personData.map { Self.initials($0.name) } ?? "KM", size: 50)
            VStack(alignment: .leading, spacing: 0) {
                Text(personData?.name ?? "Karan Mehta").font(Theme.Font.serif(21)).foregroundStyle(Theme.Palette.ink)
                Text(personData?.role ?? "Partner · Sequoia India").font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink2).padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    if let facts = personData?.facts, !facts.isEmpty {
                        ForEach(facts, id: \.self) { fact($0) }
                    } else {
                        fact("Led your A round at Visu in '22.")
                        fact("Runs late — block 20 min, not 30.")
                        fact("Asked at Soam dinner: \"show me month-6 retention.\"")
                    }
                }
                .padding(.top, 12)
            }
        }
    }
    private func fact(_ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // CSS `.person .fact .b { align-items:baseline; transform:translateY(-3px) }`
            // — the 4pt dot is baseline-aligned then LIFTED 3pt so it centers on the
            // 15pt glyph (bullet center ≈ cap-center). `.firstTextBaseline` alone
            // parks it on the baseline (~3pt low); the -3pt offset restores the lift.
            Circle().fill(Theme.Palette.ink4).frame(width: 4, height: 4).offset(y: -3)
            // CSS .person .fact line-height 1.4 × 15px ≈ 21pt pitch. Instrument
            // Serif's natural line box at 15pt already runs ~19pt, so lineSpacing(3)
            // over-led each wrapped fact and let the Person block accumulate ~2pt of
            // drift into the 'Your history' label — pull to 2 for a true ~21pt pitch.
            Text(s).font(Theme.Font.serif(15)).foregroundStyle(Theme.Palette.ink2).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let items = timelineData?.items, !items.isEmpty {
                // Inferred (subtle) entries get the hollow-ring + italic treatment
                // AND a source-cite chip, alternating twitter → email like the
                // reference. The TimelineData model carries no cite key, so derive
                // it here, in inferred order, from the canned receipts.
                let cited = Self.citedTimeline(items)
                ForEach(Array(cited.enumerated()), id: \.offset) { _, row in
                    timelineItem(date: Self.timelineDate(row.item.date),
                                 text: row.item.text,
                                 inferred: row.item.subtle ?? false,
                                 cite: row.cite)
                }
            } else {
                timelineItem(date: "2026 · 01 · 14", text: "Dinner at Soam. He asked you to keep him posted on retention.", inferred: false, cite: nil)
                timelineItem(date: "2026 · 03 · 02", text: "Liked your tweet about the M6 cohort curve — first sign he reads them.", inferred: true, cite: ("cite · twitter", .tw))
                timelineItem(date: "2026 · 04 · 11", text: "Coffee at Blue Tokai — he floated intros.", inferred: false, cite: nil)
                timelineItem(date: "2026 · 05 · 18", text: "No reply to the data-room email yet.", inferred: true, cite: ("cite · email", .em))
            }
        }
        .padding(.leading, 16)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.Palette.rule).frame(width: 1).padding(.vertical, 4)
        }
    }
    private func timelineItem(date: String, text: String, inferred: Bool, cite: (String, ReceiptKey)?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date).font(Theme.Font.mono(9.5)).tracking(0.5).foregroundStyle(Theme.Palette.ink3)
            Text(text)
                .font(inferred ? Theme.Font.serifItalic(15) : Theme.Font.serif(15))
                .foregroundStyle(Theme.Palette.ink2).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if let cite { CiteButton(label: cite.0) { open(cite.1) }.padding(.top, 5) }
        }
        // CSS `.ti { padding: 6px 0 12px }` → 6pt top + 12pt bottom per entry.
        // The bottom-only padding compressed the timeline (~12pt cumulative
        // drift), pulling the cite line up and revealing the 4th entry that the
        // reference keeps tucked behind the action-bar fade. Restore the 6pt top
        // so each entry carries the full ~18pt vertical rhythm and the 04·11 row
        // sits below the fade as in the design.
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            // CSS `.ti::before { top: 12px }` — the dot is anchored 12pt below
            // the entry's (padded) top edge, i.e. ~6pt under the 6pt top pad to
            // land on the mono date line. Offset from the padded box's topLeading.
            Circle()
                .fill(inferred ? Color.clear : Theme.Palette.ink)
                .overlay(Circle().stroke(Theme.Palette.ink, lineWidth: inferred ? 1 : 0))
                .frame(width: 7, height: 7)
                .offset(x: -20, y: 10)
        }
    }

    private var tactical: some View {
        JadeCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("OPEN WITH").font(Theme.Font.mono(9)).tracking(1.6).foregroundStyle(Theme.Palette.jadeCardInk.opacity(0.7))
                Text(tacticalData.map { "\"\($0.text)\"" } ?? "\"The churn moved — V. sent fresher M6 numbers this morning. Want me to walk you through it?\"")
                    .font(Theme.Font.serifItalic(17)).foregroundStyle(Theme.Palette.jadeCardInk).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                CiteButton(label: "2 traces · email + voice memo", tint: Color(hex: 0x1F6647)) { open(.tac) }
            }
        }
    }

    private var predictions: some View {
        VStack(spacing: 0) {
            if let items = predictionData?.items, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    predictionRow(item.text, Self.confidenceScore(item.confidence), last: idx == items.count - 1)
                }
            } else {
                predictionRow("Whether the M6 cohort held after the pricing change.", 0.94, last: false)
                predictionRow("How you're thinking about the next hire.", 0.88, last: false)
                predictionRow("Burn vs. the new plan.", 0.62, last: false)
                predictionRow("A follow-on — early, but he may float it.", 0.31, last: true)
            }
        }
    }
    private func predictionRow(_ text: String, _ score: Double, last: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text).font(Theme.Font.serifItalic(15.5)).foregroundStyle(Theme.Palette.ink2)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ConfidencePill(value: score, forced: score >= 0.8 ? .high : (score >= 0.5 ? .med : .low))
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1) } }
    }

    private var materials: some View {
        VStack(spacing: 0) {
            if let items = materialsData?.items, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    materialRow("m\(idx)", item.text, last: idx == items.count - 1)
                }
            } else {
                materialRow("m1", "M6 retention dashboard", last: false)
                materialRow("m2", "Fresh churn slide (V.'s numbers)", last: false)
                materialRow("m3", "Cap table — current", last: false)
                materialRow("m4", "The one-line ask", last: true)
            }
        }
    }
    private func materialRow(_ id: String, _ text: String, last: Bool) -> some View {
        let on = ready[id] ?? false
        return Button { ready[id] = !on } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).stroke(on ? Theme.Palette.ink : Theme.Palette.ink4, lineWidth: 1)
                    if on {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.ink)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 17, height: 17)
                Text(text).font(Theme.Font.serif(15))
                    .foregroundStyle(on ? Theme.Palette.inkFaint : Theme.Palette.ink)
                    .strikethrough(on, color: Theme.Palette.rule)
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1) } }
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.standard(0.2), value: on)
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quoteData.map { "\"\($0.text)\"" } ?? "\"Show me the curve held. The rest is narrative.\"")
                .font(Theme.Font.serifItalic(18)).foregroundStyle(Theme.Palette.ink).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(quoteData.map { "— \($0.attribution)" } ?? "— Karan, dinner at Soam, Jan 14")
                .font(Theme.Font.mono(9.5)).tracking(0.5).foregroundStyle(Theme.Palette.ink3)
        }
        .padding(.leading, 18)
        .padding(.vertical, 6)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.Palette.rule).frame(width: 2) }
    }

    // ─── Action zone ──────────────────────────────────────────────
    private var actionZone: some View {
        // CSS `.action-zone { padding:10px 22px 16px; background:
        // linear-gradient(180deg, rgba(255,255,255,0) 0%, var(--paper) 32%) }`.
        // The gradient covers the WHOLE zone (top padding + the button row) and
        // reaches opaque paper by 32% down, so scrolling content dissolves fully
        // to white well above the buttons. The previous build faded over only a
        // 32pt strip that hit full white at its bottom edge, leaving the 'Coffee
        // at Blue Tokai…' line legible right up to the button top. Paint one
        // full-zone gradient behind both the top-pad fade band and the buttons,
        // with the clear→paper transition completing in the upper third of the zone.
        HStack(spacing: 10) {
            Button {
                emitRing(); halo.setState(.delivered)
                withAnimation(Theme.Motion.standard(0.22)) { started = true }
                act(.start)   // server flips status + emits brief_acted_on (§4.a)
            } label: {
                Text(started ? "Meeting started" : "Start the meeting")
                    .font(Theme.Font.serif(17)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(started ? Theme.Palette.forest : Theme.Palette.ink))
            }
            .buttonStyle(.plain)
            Button { act(.snooze) } label: {
                Text("Snooze").font(Theme.Font.serif(15)).foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Palette.paperDeep)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.Palette.rule, lineWidth: 1)))
            }
            .buttonStyle(.plain)
        }
        // CSS action-zone padding: 10px top / 22px sides / 16px bottom — but the
        // CSS gradient reaches opaque paper at 32% of the *whole* zone (incl. the
        // ~45pt button row), i.e. ~23pt down, dissolving content to white before
        // the buttons. SwiftUI clips the gradient to this view's bounds, so the
        // opaque-paper band only covers what falls inside the zone — anything above
        // the zone's top edge stays fully legible. Pass-8 left a 28pt top pad, so
        // the band's top sat ~28pt above the buttons and the whole 4th timeline
        // entry ('2026·04·11 Coffee at Blue Tokai…', date ~32pt / body ~15pt above
        // the button top) still showed through (the pass-9 occlusion bug). Open the
        // top pad to ~56pt so the zone rises a full entry above the buttons, and
        // bring the clear→paper transition forward to ~0.18 so the gradient reaches
        // opaque paper only ~21pt down — leaving a tall solid-paper band (~35pt)
        // that fully covers the 4th-entry date (~32pt above the buttons, zone-y ~24)
        // and body (~15pt above, zone-y ~41) rows, with the soft dissolve landing
        // above them (the timeline rule fades but no body line reads through,
        // matching the reference's white gap above 'Start the meeting').
        //
        // Bottom: CSS `.action-zone` carries a 16px bottom pad. Pass-6 trimmed this
        // to 2 (reasoning the zone sat at the bottom safe area, so 16 would flood the
        // white band past the card-bottom inset), but the per-pixel reference scan
        // shows the OPPOSITE — the buttons sit ~38pt above the physical bottom with
        // ~16pt of paper below them, while at .bottom 2 the sim buttons landed only
        // ~24pt up (button bottom y≈2483 @3x vs ref ≈2441), riding 14pt low into the
        // home-indicator zone. Restore the CSS 16pt bottom pad: since the zone is
        // bottom-anchored in the ZStack, the extra 14pt lifts the whole button row UP
        // by 14pt (button bottom → ~38pt from the physical bottom, matching the ref)
        // and leaves the ~16pt of paper/gradient the reference shows below the buttons
        // before the card's rounded bottom + vignette read.
        .padding(.top, 56).padding(.horizontal, 22).padding(.bottom, 16)
        .background(
            LinearGradient(stops: [
                .init(color: Theme.Palette.paper.opacity(0), location: 0.0),
                .init(color: Theme.Palette.paper, location: 0.18),
                .init(color: Theme.Palette.paper, location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
        )
    }

    // ─── Brief actions (Start / Snooze) ───────────────────────────
    /// Act on the live brief through the repo: optimistic-local status flip +
    /// write-through (server flips status AND emits `brief_acted_on`, §4.a).
    /// No-op for the static demo brief (no server row to act on).
    private func act(_ action: BriefAction) {
        guard let id = liveBrief?.id else { return }
        Task { try? await repo.actOnBrief(id, action: action) }
    }

    // ─── Receipts ─────────────────────────────────────────────────
    private func open(_ key: ReceiptKey) {
        withAnimation(Theme.Motion.overshootStrong(0.38)) { receipt = Receipt.canned[key] }
    }
    private func emitRing() {
        let item = EORingItem(point: CGPoint(x: 150, y: 740))
        rings.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { rings.removeAll { $0.id == item.id } }
    }

    // ─── Live-data helpers ────────────────────────────────────────
    /// Seed the checkbox state from the decoded materials' `ready` flags so
    /// the live checklist opens in the brief's intended state.
    private func syncReadyFromMaterials() {
        guard let items = materialsData?.items, !items.isEmpty else { return }
        var next = ready
        for (idx, item) in items.enumerated() where next["m\(idx)"] == nil {
            next["m\(idx)"] = item.ready
        }
        ready = next
    }

    private static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }

    private static func confidenceScore(_ c: PredictionData.Item.Confidence) -> Double {
        switch c {
        case .high:   return 0.94
        case .medium: return 0.62
        case .low:    return 0.31
        }
    }

    /// Normalise a timeline date to the design's `YYYY · MM · DD` (mono, middot
    /// separated with hair spaces). Seed data stores `2026·01·14` without spaces;
    /// just pad the middots so it reads like the reference. Non-`·` formats (e.g.
    /// "May 23") are passed through untouched — they come from non-Karan briefs.
    private static func timelineDate(_ raw: String) -> String {
        guard raw.contains("·") else { return raw }
        return raw
            .split(separator: "·", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " · ")
    }

    /// Pair each timeline item with a source-cite chip when it is inferred,
    /// drawing the receipt key in inferred order (twitter → email) to match the
    /// reference's `.ti.inferred .cite` rows.
    private static func citedTimeline(_ items: [TimelineData.Item]) -> [(item: TimelineData.Item, cite: (String, ReceiptKey)?)] {
        let inferredKeys: [(String, ReceiptKey)] = [("cite · twitter", .tw), ("cite · email", .em)]
        var inferredSeen = 0
        return items.map { item in
            guard item.subtle ?? false else { return (item, nil) }
            let cite = inferredKeys[min(inferredSeen, inferredKeys.count - 1)]
            inferredSeen += 1
            return (item, cite)
        }
    }
}

// MARK: - Receipt model + sheet

enum ReceiptKey { case tw, em, tac }
struct Receipt: Identifiable {
    let id = UUID()
    let title: String
    let deck: String
    let sources: [Source]
    struct Source: Identifiable { let id = UUID(); let kind: String; let ref: String; let tint: Color }

    static let canned: [ReceiptKey: Receipt] = [
        .tw: Receipt(title: "He liked your tweet about the M6 curve.",
                     deck: "First signal Karan reads your public writing.",
                     sources: [.init(kind: "Twitter", ref: "@karanm liked · 2026-03-02 18:42", tint: Theme.Palette.tealDeep)]),
        .em: Receipt(title: "No reply yet to the data-room email.",
                     deck: "Thread is open; he read it twice on his phone.",
                     sources: [.init(kind: "Gmail", ref: "sent 2026-05-16 09:11 · 2 opens", tint: Theme.Palette.tealDeep)]),
        .tac: Receipt(title: "Lead with retention, not the round.",
                      deck: "Two traces support this.",
                      sources: [.init(kind: "Email", ref: "karan@sequoiacap.com · 2026-01-15 09:33", tint: Theme.Palette.tealDeep),
                                .init(kind: "Voice", ref: "voice memo · 2026-05-26 walk · 02:11 in", tint: Theme.Palette.forest)]),
    ]
}

private struct ReceiptSheetView: View {
    let receipt: Receipt
    let onClose: () -> Void
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0x0D141A).opacity(0.32).ignoresSafeArea()
                .onTapGesture(perform: onClose).transition(.opacity)
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Theme.Palette.ink4.opacity(0.6)).frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity).padding(.bottom, 14)
                Text(receipt.title).font(Theme.Font.serif(21)).foregroundStyle(Theme.Palette.ink).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(receipt.deck).font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink2)
                    .padding(.top, 6).padding(.bottom, 14).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(receipt.sources.enumerated()), id: \.element.id) { idx, s in
                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 5).fill(s.tint).frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.kind.uppercased()).font(Theme.Font.mono(9)).tracking(1.5).foregroundStyle(Theme.Palette.ink3)
                            Text(s.ref).font(Theme.Font.serif(13.5)).foregroundStyle(Theme.Palette.ink)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { if idx < receipt.sources.count - 1 { Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1) } }
                }
                Text("ANCHORED · OBSIDIAN SEAL").font(Theme.Font.mono(9)).tracking(1.5).foregroundStyle(Theme.Palette.tealDeep)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.5))
            )
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .shadow(color: Color(hex: 0x141820, opacity: 0.18), radius: 18, x: 0, y: -8)
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea()
    }
}
