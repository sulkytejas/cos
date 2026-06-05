import SwiftUI
import SwiftData

/// Review — approve/decline what Ayumi did overnight. A stack of review cards;
/// resolving one slides it out with a Halo pulse, and clearing the queue blooms
/// the Halo gold and reveals "All clear."
struct ReviewScreen: View {
    @Environment(HaloController.self) private var halo
    @Environment(\.modelContext) private var context
    @Environment(AtlasRepo.self) private var repo
    @Environment(NavRouter.self) private var router

    @Query(filter: #Predicate<Proposal> { $0.statusRaw == "pending" },
           sort: \.createdAt, order: .reverse)
    private var pending: [Proposal]

    enum Tone { case draft, filed, held }
    struct Item: Identifiable {
        let id = UUID()
        let tag: String; let tone: Tone; let when: String
        let lead: String; let said: String; let trail: String
        let why: String; let cite: String
        let approve: String; let decline: String
        /// Backing proposal when this card is driven by live data; nil for seed.
        var proposal: Proposal? = nil
    }

    @State private var queue: [Item] = seed
    @State private var flickerWork: DispatchWorkItem?

    /// CARDS (the overnight review queue) / DRAFT (the morning draft) toggle —
    /// the `.view-toggle` tablist from `Atlas v0.6 - Review × Halo.html`.
    enum ReviewView: String, CaseIterable { case cards = "Cards", draft = "Draft" }
    @State private var view: ReviewView = .cards

    /// Live proposals that belong on the overnight Review surface — plain
    /// review items only. "Asked" question cards (those carrying a `question`
    /// + tappable `options`) are the Capture/Ask flow's surface, not Review's
    /// stack, so they're excluded here; otherwise they'd leak into the queue as
    /// summary-only cards with no `why` line (the pass-4 content diff: the DB's
    /// only pending rows are the two ask-cards, which rendered as bare FILED
    /// cards and truncated the stack to 2).
    private var reviewProposals: [Proposal] {
        pending.filter { $0.question == nil }
    }

    /// True when the cards on screen are the authored design seed (no genuine
    /// review proposals in the DB).
    private var usingSeed: Bool { reviewProposals.isEmpty }

    /// The cards to render — genuine review proposals when present, else the
    /// authored overnight queue from `Atlas v0.6 — Review × Halo` (the design's
    /// 4-card stack, data-id 1–4).
    private var items: [Item] {
        reviewProposals.isEmpty ? queue : reviewProposals.map(Self.toViewModel)
    }

    var body: some View {
        // In-content topbar (`‹ Today` + `A REVIEW ▾`) pinned as a fixed header at
        // the top of the page card, mirroring CSS `.topbar { position:absolute;
        // top:30px }`. It replaces the shell app-mark on Review — the shell
        // suppresses its own topbar for .review (see sharedRequests) — so the bar
        // sits in the content coordinate space (no safe-area push) and stays ABOVE
        // the CARDS/DRAFT toggle with clear separation, not overlapping it.
        VStack(alignment: .leading, spacing: 0) {
            topbar
                .padding(.horizontal, 20)   // CSS .topbar padding:0 20px

            // CSS `.conv { inset: 64px 0 22px 0 }`: the scrollable conv pins at a
            // fixed 64pt from the page top (see the residual top-pad note below).
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    viewToggle
                    if view == .cards {
                        openLine
                        if items.isEmpty {
                            allClear
                        } else {
                            countRow
                            VStack(spacing: 10) {
                                ForEach(items) { item in
                                    card(item)
                                        .transition(.asymmetric(insertion: .identity,
                                                                 removal: .move(edge: .trailing).combined(with: .opacity)))
                                }
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        draftView
                    }
                    Spacer().frame(height: 24)   // CSS .conv padding-bottom 24
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)                // CSS .conv padding-top 6
            }
            // CSS `.conv` is absolutely positioned at top:64 — it does NOT stack
            // below the topbar. In SwiftUI flow the topbar's intrinsic height
            // (~24pt) already pushes the scroll content down, so the residual top
            // pad is conv-top(64) − topbar-band(30) − topbar-height(~24) ≈ 10, not
            // 34. The old 34 double-counted the topbar height and dropped the
            // toggle ~24pt too low (pass-3 spacing diff).
            .padding(.top, 10)
        }
        // CSS `.topbar { top:30px }` measured inside the page card.
        .padding(.top, 30)
        .padding(.bottom, 22)
    }

    // ─── Topbar (replaces the shell app-mark on Review) ──────────────
    /// Reference top chrome: a left `‹ Today` back-affordance (sans 14, ink-2)
    /// and a right `A REVIEW ▾` app-mark (serif-italic glyph 19 ink + mono crumb
    /// 9 ink-3), matching CSS `.back` + `.app-mark`. Mirrors SearchScreen.topbar
    /// so the two back-affordance screens read identically.
    private var topbar: some View {
        HStack(alignment: .center, spacing: 0) {
            Button { withAnimation(Theme.Motion.overshoot()) { router.go(.today) } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .regular))
                    Text("Today").font(Theme.Font.sans(14))
                }
                .foregroundStyle(Theme.Palette.ink2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("A").font(Theme.Font.serifItalic(19)).foregroundStyle(Theme.Palette.ink).tracking(-0.38)
                Text("REVIEW ▾").font(Theme.Font.mono(9)).tracking(1.44).foregroundStyle(Theme.Palette.ink3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // ─── View toggle (CARDS / DRAFT) ──────────────────────────────
    // CSS `.view-toggle`: flex pill, gap 4 / padding 4, paper-deep track with a
    // rule-soft hairline, radius 999. Buttons are mono 9.5 uppercase (.12em);
    // the active button is an ink capsule with white text.
    private var viewToggle: some View {
        HStack(spacing: 4) {
            ForEach(ReviewView.allCases, id: \.self) { v in
                Button {
                    withAnimation(Theme.Motion.standard()) { view = v }
                } label: {
                    Text(v.rawValue.uppercased())
                        .font(Theme.Font.mono(9.5))
                        .tracking(1.14)              // .12em on 9.5px ≈ 1.14pt
                        .foregroundStyle(view == v ? .white : Theme.Palette.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(view == v ? Theme.Palette.ink : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Theme.Palette.paperDeep)
                .overlay(Capsule().stroke(Theme.Palette.ruleSoft, lineWidth: 1))
        )
        .padding(.top, 2).padding(.bottom, 16)   // CSS .view-toggle margin: 2px 0 16px
    }

    // ─── Framing ──────────────────────────────────────────────────
    private var openLine: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AyumiAvatar(size: 18)
                Text("Ayumi").font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("02:14 → 06:38").font(Theme.Font.mono(9.5)).tracking(0.5).foregroundStyle(Theme.Palette.ink4)
            }
            // CSS `.framing`: italic serif, with the `.accent` run ("four things")
            // breaking to roman over a pale-teal highlighter band (see framingLine).
            framingLine
        }
        // CSS `.open-line { padding:6px 0 4px }` — the open-line block sits 6pt
        // below the toggle's 16pt bottom margin (total ≈27pt to the avatar row).
        // Without this the avatar rode ~7pt too high under the toggle (pass-5
        // open-line top-spacing diff).
        .padding(.top, 6).padding(.bottom, 4)
    }

    /// The opening line: italic serif body with the accent run "four things" set
    /// roman over a teal highlighter BAND. CSS `.accent` is
    /// `background:linear-gradient(180deg, transparent 64%, rgba(0,137,168,0.16)
    /// 64% 92%, transparent 92%)` — i.e. only the lower 64→92% of the 28.1pt line
    /// box (21px × 1.34 line-height) is tinted, a ~7.9pt baseline band, NOT a full
    /// glyph-height block and NOT an underline stroke.
    ///
    /// An AttributedString `backgroundColor` fills the WHOLE line box (the pass-5
    /// 27pt block the diff flagged), so instead the band is drawn as a thin teal
    /// rounded rect placed behind the "four things" run, and the wrapping paragraph
    /// (without any run background) rides on top. "four things" sits on line 1 in
    /// the locked seed copy, so the band anchors to the first line: its run x-offset
    /// = width of "I did ", its width = width of "four things", and it occupies the
    /// lower 28% of line 1's box. Hidden measuring `Text`s capture those widths so
    /// the band tracks the real glyph metrics rather than hardcoded pixels.
    private var framingLine: some View {
        // CSS line box: 21pt × 1.34 = 28.14pt. Band = 64%→92% of it.
        let lineBox: CGFloat = 21 * 1.34
        let bandTop = lineBox * 0.64      // ≈ 18.0pt from the line-1 top
        let bandHeight = lineBox * (0.92 - 0.64)   // ≈ 7.9pt

        return ZStack(alignment: .topLeading) {
            // The thin highlighter band behind the "four things" run on line 1.
            // `.top` alignment keeps the band's top pinned at `bandTop` regardless
            // of the zero-height prefix spacer.
            HStack(alignment: .top, spacing: 0) {
                spacerRun("I did ", italic: true)             // reserves the prefix advance → band x-offset
                accentBand(bandHeight: bandHeight)
                Spacer(minLength: 0)
            }
            .padding(.top, bandTop)

            framingText
                // CSS `.framing { line-height:1.34 }` → 28.14pt line box. Instrument
                // Serif's own line height is ~1.3×em (27.3pt at 21), so the leading
                // to ADD is only ~0.8pt, not 5 — the 5 inflated the pitch to ~32pt
                // (≈line-height 1.54) and spread the three lines apart (pass-5
                // framing leading diff). 1pt lands the pitch at ~28.3pt ≈ 1.34.
                .lineSpacing(1).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A teal rounded band exactly as wide as the roman "four things" run, sitting
    /// in the lower ~28% of line 1's box (the visible glyphs come from framingText
    /// drawn on top — this run is invisible, supplying only the band's width).
    private func accentBand(bandHeight: CGFloat) -> some View {
        Text("four things")
            .font(Theme.Font.serif(21))
            .tracking(-0.08)                                  // CSS .framing letter-spacing -0.004em ≈ -0.08pt
            .opacity(0)
            .padding(.horizontal, 1)                          // CSS .accent padding: 0 1px
            .background(RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Theme.Palette.teal.opacity(0.16)))      // CSS rgba(0,137,168,0.16) → #d5ecf1 over white
            .frame(height: bandHeight, alignment: .center)
            .clipped()
    }

    /// A zero-height invisible run reserving the horizontal advance of `s`, so the
    /// band starts exactly where "four things" begins on line 1.
    private func spacerRun(_ s: String, italic: Bool) -> some View {
        Text(s)
            .font(italic ? Theme.Font.serifItalic(21) : Theme.Font.serif(21))
            .tracking(-0.08)
            .opacity(0)
            .fixedSize()
            .frame(height: 0)
            .clipped()
    }

    /// The framing paragraph as one wrapping Text (no run background — the band is
    /// drawn behind it). Only the "four things" run is roman ink; the rest italic.
    private var framingText: Text {
        var out = AttributedString("I did ")
        out.font = .custom(Theme.Typeface.serifItalic, size: 21)
        out.foregroundColor = Theme.Palette.ink

        var accent = AttributedString("four things")
        accent.font = .custom(Theme.Typeface.serifRegular, size: 21)   // roman, breaks the italic
        accent.foregroundColor = Theme.Palette.ink

        var tail = AttributedString(" overnight and held them for you. Nothing's been sent — your call on each.")
        tail.font = .custom(Theme.Typeface.serifItalic, size: 21)
        tail.foregroundColor = Theme.Palette.ink

        return Text(out + accent + tail)
    }

    // ─── Draft view (morning draft) ───────────────────────────────
    // The DRAFT tab's full strike-line composer (`#view-draft`) is a separate
    // feature; for this pass it shows the framing line so the toggle reads
    // correctly without an empty screen.
    private var draftView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AyumiAvatar(size: 18)
                Text("Ayumi").font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("02:14 → 06:38").font(Theme.Font.mono(9.5)).tracking(0.5).foregroundStyle(Theme.Palette.ink4)
            }
            ayumiProse([
                .init("I drafted your morning "),
                .init("in your own voice.", .roman),
                .init(" Read it like rereading yourself — strike any line I got wrong, and I'll file the rest into your chapters."),
            ], size: 21, color: Theme.Palette.ink)
            // Same 21pt framing prose as the Cards tab — CSS line-height 1.34 over
            // Instrument Serif's ~1.3 natural line height needs only ~1pt of added
            // leading (was 5, which over-spread the lines).
            .lineSpacing(1).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private var countRow: some View {
        HStack(alignment: .firstTextBaseline) {
            (Text("\(items.count)").font(Theme.Font.serifItalic(22)) + Text(" to review").font(Theme.Font.serif(22)))
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button { approveAll() } label: {
                Text("APPROVE ALL").font(Theme.Font.mono(9.5)).tracking(1.0).foregroundStyle(Theme.Palette.tealDeep)
            }.buttonStyle(.plain)
        }
        .padding(.top, 18).padding(.bottom, 8)
    }

    // ─── Card ─────────────────────────────────────────────────────
    private func card(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                tagPill(item)
                Spacer()
                Text(item.when).font(Theme.Font.mono(9)).tracking(0.4).foregroundStyle(Theme.Palette.ink4)
            }
            .padding(.bottom, 8)

            // CSS `.rev .body { font-family:var(--serif); font-size:16px; color:var(--ink) }`
            // is ROMAN ink — only the inline `.said` run is italic ink-2.
            (Text(item.lead).font(Theme.Font.serif(16)).foregroundStyle(Theme.Palette.ink)
             + Text(item.said).font(Theme.Font.serifItalic(16)).foregroundStyle(Theme.Palette.ink2)
             + Text(item.trail).font(Theme.Font.serif(16)).foregroundStyle(Theme.Palette.ink))
                // CSS `.rev .body { line-height:1.4 }` → 22.4pt line box. Instrument
                // Serif's natural line height is ~20.8pt at 16, so add ~1.6pt of
                // leading, not 4 (which pushed the pitch to ~24.8pt ≈ line-height
                // 1.55 — pass-5 body line-height diff).
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)

            // CSS `.rev .why { margin-top:8px }` — drop the line (and its reserved
            // 8pt gap) entirely when a live proposal carries no rationale.
            if !item.why.isEmpty {
                Text(item.why).font(Theme.Font.serifItalic(13.5)).foregroundStyle(Theme.Palette.inkFaint)
                    // CSS `.rev .why` carries NO letter-spacing (default 0). The prior
                    // `.tracking(-0.3)` over-condensed the run ~8pt narrower than the
                    // browser's natural Instrument-Serif-Italic advance, which let one
                    // extra word ("without") slip onto card 1's first line (pass-8
                    // why-tracking diff: ref wraps "…keeps you warm" / "without
                    // overcommitting." but the sim pulled "without" up). Relaxing to 0
                    // restores the browser width so card 1 breaks one word earlier,
                    // exactly as the reference does; card 2's shorter why ("Matches 9
                    // prior saves. Want it in the Stratyfix thread?") still fits one
                    // line at this width.
                    .tracking(0)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    // The why uses the FULL card content width (no trailing inset),
                    // matching the ref's ~269pt column. At that width card 2's why
                    // ("Matches 9 prior saves. Want it in the Stratyfix thread?",
                    // ~200pt run) fits one line, while card 1's longer why greedy-
                    // breaks after "…warm" exactly as the reference balances it. A
                    // prior pass's ~26pt trailing trim narrowed the column enough to
                    // force card 2 onto two lines (pass-7 why-wrap diff), so it's
                    // removed.
                    .padding(.top, 8)
            }

            if !item.cite.isEmpty {
                Text(item.cite).font(Theme.Font.mono(9)).tracking(0.6).foregroundStyle(Theme.Palette.tealDeep).padding(.top, 8)
            }

            HStack(spacing: 8) {
                // CSS `.rev .actions button { border-radius:10px }` — a STANDARD
                // (circular) 10pt corner. `.continuous` squircles inflate the
                // apparent radius to ~18pt (pass-3 diff), so use circular corners.
                Button { approve(item) } label: {
                    Text(item.approve).font(Theme.Font.serif(14)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.Palette.ink))
                }.buttonStyle(.plain)
                Button { decline(item) } label: {
                    Text(item.decline).font(Theme.Font.serif(14)).foregroundStyle(Theme.Palette.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.Palette.paperDeep)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Palette.rule, lineWidth: 1)))
                }.buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.card))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow1()
    }

    private func tagPill(_ item: Item) -> some View {
        let (bg, fg, border): (Color, Color, Color?) = {
            switch item.tone {
            case .draft: return (Theme.Palette.tealSoft, Theme.Palette.tealDeep, nil)
            case .filed: return (Theme.Palette.paperDeep, Theme.Palette.ink2, Theme.Palette.rule)
            case .held:  return (Theme.Palette.confLowBg, Theme.Palette.confLowInk, nil)
            }
        }()
        return Text(item.tag.uppercased())
            .font(Theme.Font.mono(8.5)).tracking(1.2).foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(bg))
            .overlay(border.map { Capsule().stroke($0, lineWidth: 1) })
    }

    private var allClear: some View {
        VStack(spacing: 12) {
            Text("All clear.").font(Theme.Font.serifItalic(40)).foregroundStyle(Theme.Palette.ink)
            Text("Nothing else waiting. I'll keep watching and bring you the next thing when it matters.")
                .font(Theme.Font.serifItalic(16)).foregroundStyle(Theme.Palette.inkFaint)
                .multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60).padding(.horizontal, 24)
        .transition(.opacity)
    }

    // ─── Resolve ──────────────────────────────────────────────────

    /// Approve: live → repo.approve (optimistic-local flip + server fan-out,
    /// transition-guarded so a retry can't double-file, §4.d); seed → array removal.
    private func approve(_ item: Item) {
        if let proposal = item.proposal {
            halo.setState(.thinking)
            let id = proposal.id
            // The visible row removal animates off the @Query refresh after the
            // server write lands; the write itself isn't an animatable mutation,
            // so run it as a plain Task (wrapping it in withAnimation is a no-op).
            Task { try? await repo.approve(id) }
            scheduleHalo()
        } else {
            resolveSeed(item)
        }
    }

    /// Decline: live → repo.dismiss (optimistic-local then write-through);
    /// seed → array removal.
    private func decline(_ item: Item) {
        if let proposal = item.proposal {
            halo.setState(.thinking)
            let id = proposal.id
            // See approve(_:) — the row animates off the @Query refresh, so the
            // server write runs as a plain Task (withAnimation here is a no-op).
            Task { try? await repo.dismiss(id) }
            scheduleHalo()
        } else {
            resolveSeed(item)
        }
    }

    /// Halo flicker after a live resolve — delivered once the live queue empties.
    private func scheduleHalo() {
        flickerWork?.cancel()
        // reviewProposals still contains this proposal until the @Query
        // refreshes; the queue is empty when it was the last one.
        let empty = reviewProposals.count <= 1
        let work = DispatchWorkItem { halo.setState(empty ? .delivered : .idle) }
        flickerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    /// Seed fallback resolve — keeps the original demo array-removal animation.
    private func resolveSeed(_ item: Item) {
        halo.setState(.thinking)
        withAnimation(.timingCurve(0.34, 1.06, 0.64, 1, duration: 0.36)) {
            queue.removeAll { $0.id == item.id }
        }
        flickerWork?.cancel()
        let empty = queue.isEmpty
        let work = DispatchWorkItem { halo.setState(empty ? .delivered : .idle) }
        flickerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func approveAll() {
        if !reviewProposals.isEmpty {
            halo.setState(.thinking)
            let ids = reviewProposals.map(\.id)
            for (i, id) in ids.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 * Double(i)) {
                    // Staggered server writes; rows animate off the @Query refresh.
                    Task { try? await repo.approve(id) }
                    if i == ids.count - 1 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { halo.setState(.delivered) }
                    }
                }
            }
            return
        }
        halo.setState(.thinking)
        let items = queue
        for (i, item) in items.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 * Double(i)) {
                withAnimation(.timingCurve(0.34, 1.06, 0.64, 1, duration: 0.36)) {
                    queue.removeAll { $0.id == item.id }
                }
                if i == items.count - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { halo.setState(.delivered) }
                }
            }
        }
    }

    // ─── Mapping ──────────────────────────────────────────────────

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Map a live Proposal onto the existing card Item shape, deriving the tag /
    /// tone / button labels from the proposal type.
    private static func toViewModel(_ p: Proposal) -> Item {
        let (tag, tone, approve, decline): (String, Tone, String, String) = {
            switch p.type {
            case .todo:
                return ("Todo drafted", .draft, "Add todo", "Skip")
            case .decision, .journalEntry:
                return ("Filed", .filed, "Keep", "Archive")
            case .chapter, .chapterLink:
                return ("Held", .held, "Add", "Dismiss")
            }
        }()
        let cite: String = {
            switch (p.sourceLabel, p.sourceMeta) {
            case let (label?, meta?): return "trace · \(label) · \(meta)"
            case let (label?, nil):   return "trace · \(label)"
            case let (nil, meta?):    return "trace · \(meta)"
            default:                  return ""
            }
        }()
        return Item(
            tag: tag, tone: tone,
            when: timeFormatter.string(from: p.createdAt),
            // The summary is the card body — roman ink (`lead`), not the italic
            // ink-2 `.said` run, per CSS `.rev .body` (only inline names go italic).
            lead: p.summary ?? "", said: "", trail: "",
            why: p.reasoning ?? "", cite: cite,
            approve: approve, decline: decline,
            proposal: p
        )
    }

    // ─── Seed ─────────────────────────────────────────────────────
    // Authoritative copy mirrors `Atlas v0.6 - Review × Halo.html`: only the
    // `said` span is the italic ink-2 run; the lead/trail stay roman ink.
    static let seed: [Item] = [
        .init(tag: "Draft reply", tone: .draft, when: "03:42",
              lead: "Reply to ", said: "Karan", trail: " — \"Sending the M6 cohort slice ahead of 2:30. See you then.\"",
              why: "He asked twice; a short ack keeps you warm without overcommitting.",
              cite: "trace · gmail thread + your calendar", approve: "Send it", decline: "Not yet"),
        .init(tag: "Filed", tone: .filed, when: "04:10",
              lead: "Filed 23 newsletters; surfaced ", said: "one", trail: " — the SaaS retention teardown you star things like.",
              why: "Matches 9 prior saves. Want it in the Stratyfix thread?",
              cite: "trace · inbox rules + save history", approve: "Keep in thread", decline: "Just archive"),
        .init(tag: "Held", tone: .held, when: "05:05",
              lead: "A recruiter pinged about a Dublin role. I ", said: "held it", trail: " — looked relevant to Ireland MBA.",
              why: "Could be noise. Promote to the chapter, or dismiss?",
              cite: "trace · linkedin + Ireland watcher", approve: "Add to Ireland", decline: "Dismiss"),
        .init(tag: "Todo drafted", tone: .draft, when: "06:30",
              lead: "Drafted a todo: ", said: "\"Confirm V.'s new 11:30 studio time.\"", trail: "",
              why: "Her email moved the sitting; you haven't replied.",
              cite: "trace · gmail + calendar", approve: "Add todo", decline: "Skip"),
    ]
}
