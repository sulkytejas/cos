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

    /// The morning memo (Today agentic flow v1) — the redlineable letter the
    /// worker's nightly daily-scan composed. We pull the newest morning turn and
    /// surface its `memo` ABOVE the overnight review queue: each disposition line
    /// is tappable to strike, then "Keep" seals it. Sorted newest-first so a
    /// freshly-synced morning turn replaces the prior day's the moment it lands.
    @Query(filter: #Predicate<Turn> { $0.kindRaw == "morning" },
           sort: \.createdAt, order: .reverse)
    private var morningTurns: [Turn]

    /// The single morning turn whose memo we render — the most recent one.
    private var morningTurn: Turn? { morningTurns.first }

    /// Local strike/keep state is held on the SwiftData `Turn` (patched optimistically
    /// by `repo.strikeMemoLine`/`keepMemo`), but the redline needs to re-read the memo
    /// snapshot whenever a line is struck so the row redraws at once. This counter
    /// is bumped on every strike/keep to force the memo card to recompute from the
    /// (already-mutated) model — SwiftData's @Query won't always re-emit on an
    /// in-place JSON-blob edit to a single row, so we nudge the view explicitly.
    @State private var memoRevision = 0

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

    /// Ink on the held sentences this sitting — per item, the struck word
    /// indices (the SAME pen as the memo above; one gesture grammar). Local
    /// until the letter seals — ink stays visible while reviewing, then any
    /// inked sentence commits as a dismissal when the letter is put down.
    /// Clean sentences approve themselves — silence is consent.
    @State private var heldInk: [UUID: [Int]] = [:]
    @Environment(\.scenePhase) private var scenePhase
    /// When the page became visible — the seal's engagement guard. PageShell
    /// transitions mount/unmount neighbors briefly; a letter must only seal
    /// when it was actually HELD (visible a beat, or marked), never on a
    /// transient flash-through.
    @State private var appearedAt: Date? = nil
    /// The user marked something this sitting — seals on leave regardless of dwell.
    @State private var engaged = false

    /// CARDS (the overnight review queue) / DRAFT (the morning draft) toggle —
    /// the `.view-toggle` tablist from `Atlas v0.6 - Review × Halo.html`.
    enum ReviewView: String, CaseIterable { case cards = "Letter", draft = "Draft" }
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
                    // ONE page, no tabs, no cards — the draft idiom is the design:
                    // bare ink on paper. Ayumi's framing line, then the morning
                    // prose (word-level redline), then everything held overnight as
                    // sentences. Strike what's wrong; the review ENDS when the
                    // letter is put down (leave the page / background the app):
                    // strikes commit as dismissals, the untouched file themselves —
                    // silence is consent — and the page collapses to its quiet
                    // KEPT stamp for the day.
                    draftView
                    morningMemoSection
                    if isLetterDraft {
                        if !items.isEmpty { heldSection }
                    } else if items.isEmpty {
                        allClear
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
        // The review ENDS when the letter is put down: navigating away or
        // backgrounding the app seals it (no confirm button — the ceremony is
        // read, mark, walk away). Guarded by engagement: a transient mount
        // during a page transition must never seal an unread letter.
        .onAppear { appearedAt = Date() }
        .onDisappear {
            if heldLongEnough { sealLetter() }
            appearedAt = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, heldLongEnough { sealLetter() }
        }
    }

    /// The letter counts as "held" after a beat of real reading, or the moment
    /// anything was struck this sitting.
    private var heldLongEnough: Bool {
        if engaged { return true }
        guard let t = appearedAt else { return false }
        return Date().timeIntervalSince(t) > 2.5
    }

    /// True while today's morning memo is still redlineable.
    private var isLetterDraft: Bool {
        morningTurn?.memo?.status == "draft"
    }

    // ─── Held for you — the overnight queue as prose ──────────────
    // Every pending proposal is a SENTENCE in the letter, not a card. A stroke
    // or tap strikes the whole sentence (a proposal is an atomic decision —
    // the word-pen is for the memo's editorial text above). Struck ink stays
    // visible until the letter seals; nothing vanishes mid-read.

    /// The held items continue the letter as plain sentences — same page, same
    /// pen, nothing announcing them. The `said` run is italic in card copy; the
    /// default prose voice here is italic with *roman* markup, so lead/trail
    /// get re-encoded as roman runs.
    private var heldLines: [TurnMemoLine] {
        items.map { item in
            var text = ""
            if !item.lead.isEmpty { text += "*\(item.lead)*" }
            text += item.said
            if !item.trail.isEmpty { text += "*\(item.trail)*" }
            return TurnMemoLine(
                id: item.id.uuidString,
                text: text,
                refKind: nil, refId: nil,
                struck: false,
                struckWords: heldInk[item.id])
        }
    }

    private var heldSection: some View {
        RedlineProse(lines: heldLines, size: 16) { lineIdx, struckWords in
            guard items.indices.contains(lineIdx) else { return }
            engaged = true
            heldInk[items[lineIdx].id] = struckWords.isEmpty ? nil : struckWords
        }
        .padding(.top, 14)
    }

    /// Put the letter down: strikes become dismissals, the untouched approve
    /// themselves (silence is consent), the memo seals to its KEPT stamp.
    /// Idempotent — only fires while today's letter is still a draft.
    private func sealLetter() {
        guard let turn = morningTurn, turn.memo?.status == "draft" else { return }
        halo.setState(.thinking)
        for item in items {
            guard let p = item.proposal else { continue }
            let id = p.id
            // Any ink on the sentence = no; a clean sentence files itself.
            if !(heldInk[item.id] ?? []).isEmpty {
                Task { try? await repo.dismiss(id) }
            } else {
                Task { try? await repo.approve(id) }
            }
        }
        queue.removeAll()
        heldInk.removeAll()
        engaged = false
        keep(turn)
        flickerWork?.cancel()
        let work = DispatchWorkItem { halo.setState(.delivered) }
        flickerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
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
            // The page's ONLY instruction — quiet mono, the draft idiom's
            // caption style. No oversized framing prose: the letter speaks in
            // one voice and one size; the chrome whispers.
            Text("STRIKE WHAT'S WRONG — PUTTING THE LETTER DOWN FILES THE REST")
                .font(Theme.Font.mono(9.5)).tracking(1.0)
                .foregroundStyle(Theme.Palette.ink4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.top, 2)
    }

    // ─── Morning memo redline (Today agentic flow v1) ──────────────
    // The redlineable letter from the nightly daily-scan, rendered in the same
    // letter/card idiom as the review cards (white card fill, shadow1). Each memo
    // line is a disposition (held / folded / prepared / watching) the user can
    // strike; striking teaches Ayumi what doesn't matter, and a struck line that
    // references a still-pending proposal also dismisses it (handled in the repo /
    // server). "Keep" seals the memo to `kept` and collapses the card to a single
    // quiet stamp; an already-kept memo renders collapsed on every later visit.

    @ViewBuilder
    private var morningMemoSection: some View {
        // `memoRevision` is read so the card recomputes after an in-place strike/keep
        // patch to the turn's memo JSON (see the @State note above).
        let _ = memoRevision
        if let turn = morningTurn, let memo = turn.memo {
            if memo.status == "kept" {
                memoKeptRow(turn: turn, memo: memo)
                    .padding(.bottom, 18)
            } else {
                memoCard(turn: turn, memo: memo)
                    .padding(.bottom, 18)
            }
        }
    }

    /// The morning prose, bare on the page (the draft idiom — no card chrome,
    /// no header band): redlineable at WORD granularity. Drag sideways to
    /// strike a span (snaps to whole words, haptic tick per word), tap a
    /// single word to fine-tune, drag again over struck ink to erase. A
    /// fully-struck sentence fires the full forget/dismiss effects; a partial
    /// strike is recorded on the line and teaches without deleting.
    private func memoCard(turn: Turn, memo: TurnMemo) -> some View {
        RedlineProse(lines: memo.lines, size: 16) { lineIdx, struckWords in
            commitRedline(turn: turn, lineIdx: lineIdx, struckWords: struckWords)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    /// One disposition line — tap toggles its struck flag. Struck lines render
    /// The sealed memo — a single quiet stamp row replacing the card once kept.
    /// mono "KEPT · HH:mm" + the verdict (turn.body) as a serif-italic one-liner.
    private func memoKeptRow(turn: Turn, memo: TurnMemo) -> some View {
        // Prefer the instant the user kept it; fall back to the turn's createdAt.
        let when = memo.keptAt.flatMap(AtlasISO.date) ?? turn.createdAt
        let stamp = Self.timeFormatter.string(from: when)
        let runs = parseAyumiMarkup(turn.body).first ?? [ProseRun(turn.body)]
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("KEPT · \(stamp)")
                .font(Theme.Font.mono(9.5)).tracking(1.14)
                .foregroundStyle(Theme.Palette.ink3)
                .fixedSize()
            ayumiProse(runs, size: 14.5, color: Theme.Palette.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    // ─── Memo mutations (write-through repo, optimistic local) ─────

    /// Commit one line's redline state from the word-level gesture.
    ///
    /// `struckWords` is the line's complete struck set after the stroke/tap.
    /// Full coverage → the classic whole-line strike (struck=true: backing
    /// notes forgotten, pending proposal dismissed). Empty → clean un-strike.
    /// Anything between → the PUT: struck=false + the word list, recorded on
    /// the line, no destructive effects.
    ///
    /// We patch the SwiftData `Turn` IN PLACE first (instant ink — the card
    /// reads the memo straight off the model and `memoRevision` forces the
    /// recompute), then fire the repo write-through, whose own optimistic
    /// patch is idempotent against ours.
    private func commitRedline(turn: Turn, lineIdx: Int, struckWords: [Int]) {
        guard var memo = turn.memo, memo.lines.indices.contains(lineIdx) else { return }
        let line = memo.lines[lineIdx]
        let totalWords = tokenizeMemoLines([line]).count
        let full = totalWords > 0 && struckWords.count >= totalWords
        let none = struckWords.isEmpty
        let words: [Int]? = (full || none) ? nil : struckWords

        memo.lines[lineIdx].struck = full
        memo.lines[lineIdx].struckWords = words
        turn.memo = memo
        memoRevision &+= 1
        engaged = true

        let turnID = turn.id
        let lineId = line.id
        Task {
            try? await repo.strikeMemoLine(
                turnID: turnID, lineId: lineId, struck: full, struckWords: words)
        }
    }

    /// Keep (seal) the memo — flip status to `kept` so the card collapses to the
    /// stamp row, then fire the repo write-through (idempotent; an already-kept memo
    /// is a server no-op). The local flip drives the collapse animation immediately.
    private func keep(_ turn: Turn) {
        let id = turn.id
        if var memo = turn.memo, memo.status != "kept" {
            memo.status = "kept"
            memo.keptAt = AtlasISO.string(Date())
            memo.keptBy = "user"
            turn.memo = memo
        }
        memoRevision &+= 1
        Task { try? await repo.keepMemo(turnID: id) }
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
