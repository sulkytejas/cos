import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  LivingChapterView.swift — THE LIVING CHAPTER (North India).
//  README §PART 2 + atlas-trip.css. A single vertical scroll that makes
//  Ayumi's reasoning visible: built from one flight email, opened mid-
//  trip (day 5, Rishikesh).
//
//  Sections, in order (inside the `.conv` scroll):
//    1. Masthead / framing            (avatar + meta + italic framing + title)
//    2. The route                     (RouteTimeline — stops + legs + provenance)
//    3. Spent so far                  (SpendSection — big ₹, stacked bar, legend)
//    4. You'd love, near you          (rec cards w/ taste-signal justification)
//    5. Tracking, live                (stat cards from Health + Maps)
//    6. To serve you better           (ConnectorsSection — feeding vs available)
//    7. How I built this (receipts)   (BuildThread + cite → ReceiptsSheet)
//
//  Interactions:
//    • Past stops collapse to a `.mini`; tap to expand (current/upcoming stay open).
//    • A past leg's 26px pencil opens a CorrectionSheet pre-loaded with the
//      seeded-wrong "Flew to Pantnagar · ₹4,900". Submitting reconciles: the leg
//      rewrites (mode + fare + `told`), the spend total ANIMATES and the legend
//      rebalances, and a dark ripple toast states what changed + "what I learned".
//    • Granting a connector flips it to "Linked", rewrites its role, blooms the halo.
//    • "cite" / "how I know" opens a ReceiptsSheet (backdrop closes).
//
//  Data: `repo.northIndiaTrip()` (seeded offline) + repo.correctLeg / grantConnector.
//  All AI/reconcile logic stays server-routed in a later phase; here the seeded
//  reconcile is applied locally over the mutable trip copy.
// ════════════════════════════════════════════════════════════════════

struct LivingChapterView: View {
    /// Optional dismiss (back to Chapters). Nil when launched directly via the
    /// `--chapter north` debug arg.
    var onBack: (() -> Void)? = nil

    @Environment(AtlasRepo.self) private var repo
    @Environment(HaloController.self) private var halo

    // ── Mutable trip state (reconcile/grant mutate this copy) ──────────
    @State private var trip: Trip = NorthIndiaSeed.northIndia
    @State private var didLoad = false

    // Route collapse — which past stops are expanded. Past stops start collapsed.
    @State private var expandedStops: Set<String> = []

    // Spend reconcile flash.
    @State private var spendFlashing = false

    // Connector grants (optimistic relabel survives re-render).
    @State private var grantedConnectors: Set<String> = []

    // Sheets / toast.
    @State private var activeCorrection: Correction? = nil
    @State private var receiptContext: ReceiptContext? = nil
    @State private var ripple: Ripple? = nil
    @State private var rippleWork: DispatchWorkItem? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            scroll

            // Sheets + toast layer (above the scroll, within the page surface).
            if let correction = activeCorrection {
                CorrectionSheet(
                    correction: correction,
                    onSubmit: { answer in submitCorrection(correction, answer: answer) },
                    onClose: { closeCorrection() }
                )
                .zIndex(30)
            }

            if let ctx = receiptContext {
                ReceiptsSheet(
                    context: ctx,
                    receipts: trip.receipts,
                    onClose: { withAnimation(Theme.Motion.overshoot(0.4)) { receiptContext = nil } }
                )
                .zIndex(30)
            }

            if let r = ripple {
                RippleToast(ripple: r)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // CSS `.page { background:#ffffff; box-shadow: inset 0 0 80px
        // rgba(20,24,32,0.04) }` — pure-white paper with a soft inward vignette
        // that very slightly darkens it toward the card edges (edge paper reads
        // ~RGB 250,250,250). PageShell draws this vignette on the page card BEHIND
        // the chapter, but this view's own opaque paper fill sits ABOVE it and
        // would otherwise paint the edges flat #FFFFFF — so re-draw the same inset
        // glow here, over the paper, with the SAME geometry PageShell uses (an
        // inward-blurred 26pt rounded-rect stroke in the cool-grey page ink at 4%,
        // clipped to the 32pt page corner). Base fill stays #FFFFFF.
        .background(
            Theme.Palette.paper.overlay(pageVignette)
        )
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        // Instant offline render from the seed, then upgrade to the server
        // projection (the seed + the user's persisted corrections + grants).
        trip = repo.northIndiaTrip()
        Task {
            let fetched = await repo.loadTrip(id: "north")
            trip = fetched
            // Reflect any persisted leg corrections in the collapse state so a
            // previously-corrected past stop is already expanded on load. A leg's
            // corrected fact lives on its DOWNSTREAM stop (`toStop`) — leg ids are
            // `leg-*` and never collide with stop ids, so expand by `toStop`.
            for leg in fetched.legs where leg.corrected {
                if fetched.stops.contains(where: { $0.id == leg.toStop && $0.state == .done }) {
                    expandedStops.insert(leg.toStop)
                }
            }
        }
    }

    // MARK: - The scroll

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                routeSection
                SpendSection(spend: trip.spend, flashing: spendFlashing,
                             onCite: { openReceipts(.spend) })
                recsSection
                trackingSection
                ConnectorsSection(connectors: trip.connectors,
                                  granted: $grantedConnectors,
                                  onGrant: grantConnector)
                receiptsSection
                Spacer().frame(height: 120)
            }
            .padding(.horizontal, Theme.Layout.screenPad)
            .padding(.top, 6)         // CSS .conv padding-top 6
        }
        .scrollIndicators(.hidden)
        // CSS `.conv { inset: 64px 0 0 0 }` — viewport inset inside the page so
        // scrolled content clips at the header band instead of riding over it.
        .padding(.top, 64)
    }

    // MARK: - 1 · Masthead / framing

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back affordance (only when embedded under Chapters), with the
            // trailing mono-caps chapter label on the right of the same row —
            // ref: "‹ Chapters … NORTH INDIA ▾".
            if let onBack {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 6) {
                            // CSS `.back svg` is a 1.4px-stroke chevron — use a
                            // thin (.regular) weight rather than semibold so it
                            // reads as the light line-art, not a heavy glyph.
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .regular))
                            Text("Chapters").font(Theme.Font.sans(14))
                        }
                        // CSS `.back { color:var(--ink-2) }` — the darker ink-2,
                        // not the ink-3 meta gray.
                        .foregroundStyle(Theme.Palette.ink2)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 8)
                    Text("\(trip.title.uppercased()) ▾")
                        .font(Theme.Font.mono(9.5))
                        .tracking(1.5)
                        .foregroundStyle(Theme.Palette.ink3)
                        .fixedSize()
                }
                // The back row sits in the topbar band; the Ayumi meta opens the
                // brief below it. In the design the topbar (top:30) and the
                // brief-open meta are separated by the `.conv` inset (64) + the
                // brief-open top padding (8) — a ~24pt baseline-to-avatar gap.
                // 14 read too tight (Ayumi rode up ~11pt); 24 drops it to match.
                .padding(.bottom, 24)
            }

            // avatar + meta + "built …"
            HStack(spacing: 8) {
                AyumiAvatar(size: 18)
                Text("Ayumi")
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize()                       // never wrap the name
                Spacer(minLength: 8)
                // `.brief-open .meta .when` — mono 9.5, ink-4, NOT uppercased.
                // Single line, right-aligned; truncates before it crowds the name.
                Text(trip.meta)
                    .font(Theme.Font.mono(9.5))
                    .tracking(0.4)
                    .foregroundStyle(Theme.Palette.ink4)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }
            .padding(.bottom, 12)

            // The book-serif-italic framing sentence; the accent word ("day 5")
            // carries a single thin teal underline (ref), not a filled block.
            framingView

            // Big serif title. CSS `.brief-title { font-size:46px;
            // letter-spacing:-0.02em }` → tracking -0.92pt (-0.02em × 46),
            // which compresses the glyph advance ~5% to the reference width.
            Text("\(trip.title).")
                .font(Theme.Font.serifItalic(46))
                .tracking(-0.92)
                .foregroundStyle(Theme.Palette.ink)
                // CSS `.brief-title { margin: 18px 0 2px; line-height: 0.98 }`.
                // Instrument Serif's SwiftUI line box adds ~11pt of leading BELOW
                // the glyphs at 46pt, so the default gap to the sub reads ~21pt vs
                // the mock's ~12pt. Pull the sub up by -8 (the sibling BriefScreen's
                // proven amount) so it lands ~2pt under the title per `margin:0 0 2px`.
                .padding(.top, 18)
                .padding(.bottom, -8)

            // Sub-line: dates · stops · day N. Matches `.brief-sub` — the leading
            // date chunk is teal-deep (`.when`), then a 1×9 hairline divider, then
            // the rest in ink-3. CSS `.brief-title` margin-bottom 2px → ~2pt below.
            subLine
                .padding(.top, 2)
        }
    }

    /// The masthead sub-line, split on the first " | " so the date range reads
    /// teal-deep (`.brief-sub .when`) with a thin divider before the place names
    /// (`.div`) — ref: teal "May 30 – Jun 11" │ gray "Nainital · Rishikesh · Kasol".
    @ViewBuilder
    private var subLine: some View {
        let parts = trip.dateRange.components(separatedBy: " | ")
        HStack(spacing: 8) {
            if let when = parts.first {
                Text(when)
                    .font(Theme.Font.mono(10))
                    .tracking(0.4)
                    .foregroundStyle(Theme.Palette.tealDeep)
                if parts.count > 1 {
                    Rectangle().fill(Theme.Palette.rule).frame(width: 1, height: 9)
                    Text(parts.dropFirst().joined(separator: " | "))
                        .font(Theme.Font.mono(10))
                        .tracking(0.4)
                        .foregroundStyle(Theme.Palette.ink3)
                }
            }
        }
    }

    /// The design's roman (upright) exception inside the otherwise serif-italic
    /// framing — CSS `.brief-open .framing .roman { font-style:normal }` wraps the
    /// phrase "one flight confirmation" so the forwarded artifact reads upright
    /// against the italic body. Fixed design constant (the data model carries no
    /// roman-span field); matched as a contiguous run in `framingWords`.
    private let framingRoman = "one flight confirmation"

    /// The framing sentence as a wrapping word-flow. Non-accent words are
    /// Instrument Serif italic `--ink` (CSS `.brief-open .framing`: 21px, line-
    /// height 1.34); the `framingAccent` words ("day 5") carry a pale-teal
    /// highlighter swash (`em.accent` linear-gradient → rgba(0,137,168,0.16)),
    /// NOT an underline. The `framingRoman` run ("one flight confirmation")
    /// renders UPRIGHT serif (`.roman`). Matching is punctuation-tolerant so an
    /// accent word followed by a comma ("day 5,") still highlights.
    @ViewBuilder
    private var framingView: some View {
        let romanIndices = romanWordIndices
        // CSS `line-height:1.34 × 21px = 28.14pt` pitch. Instrument Serif's
        // intrinsic line box is 27.3pt at 21pt (hhea ascent 990 − descent 310,
        // unitsPerEm 1000), so only ~0.85pt of inter-line gap lands the 28pt
        // pitch — NOT the looser 6pt (which read as 33.3pt, pushing later
        // content down). Regular + italic share the 27.3pt box, so the roman
        // run never changes the row pitch.
        FlowLayout(spacing: 5, lineSpacing: 0.85) {
            ForEach(Array(framingSegments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .word(let idx, let word):
                    FramingWord(word: word, roman: romanIndices.contains(idx))
                case .accent(let phrase, let trailing):
                    // CSS markup wraps "day 5" in ONE `<em class="accent">`, so the
                    // highlighter swash is a SINGLE continuous band across the whole
                    // phrase (including the inter-word space) — not a per-word block
                    // with a gap. The trailing comma sits OUTSIDE the `<em>`, so it
                    // renders un-highlighted, hugging the band with no flow spacing.
                    FramingAccentRun(phrase: phrase, trailing: trailing)
                }
            }
        }
    }

    /// One item in the framing flow: either a plain word (carrying its original
    /// index so the roman lookup still resolves) or the merged accent run.
    private enum FramingSegment {
        case word(idx: Int, word: String)
        /// The continuous accent phrase ("day 5") + any trailing punctuation that
        /// was attached to the last accent word ("," ) but must NOT be highlighted.
        case accent(phrase: String, trailing: String)
    }

    /// Collapse the contiguous `framingAccent` run into a SINGLE `.accent` segment
    /// so its highlighter swash is one continuous band; every other word stays a
    /// `.word` segment carrying its original index (for the roman lookup).
    private var framingSegments: [FramingSegment] {
        let words = framingWords
        guard let range = accentWordRange else {
            return words.enumerated().map { .word(idx: $0.offset, word: $0.element) }
        }
        // The accent phrase is the trimmed accent words joined with single spaces
        // ("day 5"); the trailing punctuation is whatever clung to the LAST accent
        // word after trimming ("5," → trailing ","), so the comma reads outside the
        // band exactly as the CSS `<em>` boundary puts it.
        let phrase = range.map { trimPunct(words[$0]) }.joined(separator: " ")
        let last = words[range.upperBound - 1]
        // Trailing punctuation = the last accent word minus its trimmed core
        // ("5," → trailing ","). Accent words carry no leading punctuation, so the
        // core is a prefix and the remainder is the trailing suffix.
        let core = trimPunct(last)
        let trailing = last.hasPrefix(core) ? String(last.dropFirst(core.count)) : ""
        var segs: [FramingSegment] = []
        for (idx, word) in words.enumerated() {
            if idx == range.lowerBound {
                segs.append(.accent(phrase: phrase, trailing: trailing))
            } else if range.contains(idx) {
                continue   // folded into the single accent segment above
            } else {
                segs.append(.word(idx: idx, word: word))
            }
        }
        return segs
    }

    /// The contiguous index range in `framingWords` that matches the
    /// `framingAccent` phrase, word-for-word (punctuation-tolerant) — the same
    /// matching `romanWordIndices` uses, so a comma on the last accent word
    /// ("day 5,") still resolves the run.
    private var accentWordRange: Range<Int>? {
        let target = (trip.framingAccent ?? "")
            .split(separator: " ").map { trimPunct(String($0)) }
        guard !target.isEmpty else { return nil }
        let words = framingWords.map { trimPunct($0) }
        guard words.count >= target.count else { return nil }
        for start in 0...(words.count - target.count) {
            if Array(words[start..<(start + target.count)]) == target {
                return start..<(start + target.count)
            }
        }
        return nil
    }

    /// The word indices inside `framingWords` that fall within the `framingRoman`
    /// phrase — found as the first contiguous run whose trimmed words match the
    /// phrase's words in order, so the upright span survives punctuation on the
    /// surrounding words.
    private var romanWordIndices: Set<Int> {
        let target = framingRoman.split(separator: " ").map { trimPunct(String($0)) }
        guard !target.isEmpty else { return [] }
        let words = framingWords.map { trimPunct($0) }
        guard words.count >= target.count else { return [] }
        for start in 0...(words.count - target.count) {
            if Array(words[start..<(start + target.count)]) == target {
                return Set(start..<(start + target.count))
            }
        }
        return []
    }

    /// Strip leading/trailing punctuation so accent matching survives commas, etc.
    private func trimPunct(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet.punctuationCharacters)
    }

    /// The framing split into words, preserving punctuation as part of each word
    /// so the flow reads naturally.
    private var framingWords: [String] {
        trip.framing.split(separator: " ").map(String.init)
    }

    // MARK: - 2 · The route

    private var routeSection: some View {
        ChapterSection(title: "The route", cite: "how I know",
                       onCite: { openReceipts(.route) }) {
            RouteTimeline(
                stops: trip.stops,
                legs: trip.legs,
                expanded: $expandedStops,
                onCorrect: { targetId in openCorrection(targetId) },
                canCorrect: { legId in trip.correction(forTarget: legId) != nil }
            )
        }
    }

    // MARK: - 4 · You'd love, near you

    private var recsSection: some View {
        ChapterSection(title: "You'd love, near you") {
            VStack(spacing: 11) {
                ForEach(trip.recommendations) { rec in RecCard(rec: rec) }
            }
        }
    }

    // MARK: - 5 · Tracking, live

    private var trackingSection: some View {
        ChapterSection(title: "Tracking, live") {
            VStack(spacing: 11) {
                // 2-up grid, with the wide card spanning the row.
                let narrow = trip.tracking.filter { !$0.wide }
                let wide = trip.tracking.filter { $0.wide }
                HStack(spacing: 11) {
                    ForEach(narrow) { stat in TrackingCard(stat: stat) }
                }
                ForEach(wide) { stat in TrackingCard(stat: stat) }
            }
        }
    }

    // MARK: - 7 · How I built this (receipts)

    private var receiptsSection: some View {
        ChapterSection(title: "How I built this", cite: "cite",
                       onCite: { openReceipts(.all) }) {
            BuildThread(steps: trip.buildSteps)
        }
    }

    // MARK: - Correction → reconcile

    private func openCorrection(_ targetId: String) {
        // Correction prepared for this target (the seeded Delhi→Nainital fix).
        guard let c = trip.correction(forTarget: targetId) else { return }
        withAnimation(Theme.Motion.overshoot(0.4)) { activeCorrection = c }
        halo.setState(.thinking)
    }

    private func closeCorrection() {
        withAnimation(Theme.Motion.overshoot(0.4)) { activeCorrection = nil }
        if ripple == nil { halo.setState(.idle) }
    }

    private func submitCorrection(_ correction: Correction, answer: String) {
        // Close the sheet immediately; the reconcile (server or seeded) resolves
        // the leg + the ripple.
        withAnimation(Theme.Motion.overshoot(0.4)) { activeCorrection = nil }

        // Apply the local rewrite optimistically so the leg + spend animate at
        // once (the server returns the authoritative ripple copy). `targetId` is
        // the LEG id (== server leg ids), so this matches the leg directly. The
        // reconcile RULE is the SAME one the server applies (mirrored in
        // NorthIndiaSeed.rule), so the optimistic mode/fare/spend land exactly
        // where the server's recompute will — no visible jump on the round-trip.
        let rule = NorthIndiaSeed.rule(legId: correction.targetId, answer: answer)
        var correctedToStop: String?
        if let legIdx = trip.legs.firstIndex(where: { $0.id == correction.targetId }) {
            correctedToStop = trip.legs[legIdx].toStop
            trip.legs[legIdx].corrected = true

            if let rule {
                // Scripted reconcile (the seeded Delhi→Nainital flight): adopt the
                // rule's mode + fare. Move the leg's CURRENT fare out of whichever
                // segment it sits in now (flights while it's still the seeded
                // flight, travel once already corrected) and book the new ground
                // fare into travel — so a re-correction rebalances from the right
                // base, never double-subtracting. This matches the server, which
                // recomputes from the seed base + the latest leg patch.
                let oldMode = trip.legs[legIdx].mode
                let oldFare = parseFare(trip.legs[legIdx].fare)
                let wasFlight = isFlightMode(oldMode)
                trip.legs[legIdx].mode = rule.mode
                trip.legs[legIdx].fare = NorthIndiaSeed.formatFare(rule.fareRupees)
                trip.legs[legIdx].booked = true
                withAnimation(.easeInOut(duration: 0.6)) {
                    if wasFlight {
                        trip.spend.segments.flights = max(0, trip.spend.segments.flights - oldFare)
                    } else {
                        trip.spend.segments.travel = max(0, trip.spend.segments.travel - oldFare)
                    }
                    trip.spend.segments.travel += rule.fareRupees
                    trip.spend.total = max(0, trip.spend.total - oldFare + rule.fareRupees)
                }
            } else {
                // Generic reconcile (any other past leg): record the words as the
                // new mode, no spend shift — mirrors the server's fallback.
                trip.legs[legIdx].mode = answer
            }
        }

        // Expand the corrected past stop (the leg's downstream stop) so the rewrite
        // is on screen — leg ids never collide with stop ids, so resolve via toStop.
        if let toStop = correctedToStop,
           trip.stops.contains(where: { $0.id == toStop && $0.state == .done }) {
            // `Set.insert` returns a (inserted, member) tuple; discard it so the
            // withAnimation closure is Void (the expansion still animates).
            withAnimation(Theme.Motion.standard(0.36)) { _ = expandedStops.insert(toStop) }
        }

        // Flash the spend total jade, then settle.
        spendFlashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(Theme.Motion.standard(0.3)) { spendFlashing = false }
        }

        // Halo: think → deliver (Ayumi reconciled).
        halo.setState(.delivered)

        // Reconcile through the repo (server-backed; seeded offline) — the
        // authoritative ripple {changed, learned} + a durable learned preference
        // that tunes the NEXT suggestion. Adopt the server's recomputed spend so
        // the optimistic estimate settles to the truth.
        Task {
            let result = await repo.correctLeg(legId: correction.targetId, answer: answer)
            showRipple(result.ripple)
            // Re-pull the server projection so the spend total + the retuned Kasol
            // suggestion reflect the persisted correction exactly.
            let refreshed = await repo.loadTrip(id: "north")
            if refreshed.spend.total != trip.spend.total {
                withAnimation(.easeInOut(duration: 0.5)) { trip.spend = refreshed.spend }
            }
            trip.legs = refreshed.legs
        }
    }

    /// Numeric rupees from a fare label ("₹4,900" → 4900; "" → 0).
    private func parseFare(_ fare: String) -> Int {
        Int(fare.filter(\.isNumber)) ?? 0
    }

    /// Whether a leg-mode label reads as air travel (its fare sits in `flights`).
    private func isFlightMode(_ mode: String) -> Bool {
        let m = mode.lowercased()
        return m.contains("flew") || m.contains("flight") || m.contains("fly")
    }

    private func showRipple(_ r: Ripple) {
        rippleWork?.cancel()
        withAnimation(Theme.Motion.overshoot(0.46)) { ripple = r }
        let work = DispatchWorkItem {
            withAnimation(Theme.Motion.overshoot(0.46)) { ripple = nil }
            halo.setState(.idle)
        }
        rippleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    // MARK: - Connector grant

    private func grantConnector(_ conn: Connector) {
        // Bloom the halo — progressive capability via consent.
        halo.setState(.delivered)
        // Grant through the repo (server-backed; no-op offline). On the server
        // path Ayumi returns the rewritten role/unlock copy; adopt it so the row
        // reads what Ayumi can now do (the ConnectorsSection already flipped it to
        // "Linked" optimistically via `granted`).
        Task {
            guard let copy = await repo.grantConnector(conn.id) else { return }
            if let idx = trip.connectors.firstIndex(where: { $0.id == conn.id }) {
                withAnimation(Theme.Motion.standard(0.3)) {
                    trip.connectors[idx].role = copy.role
                    // The post-grant role the row shows is `grantedRole`; adopt the
                    // server's authoritative "what Ayumi can now do" copy there too.
                    trip.connectors[idx].grantedRole = copy.role
                    trip.connectors[idx].unlockCopy = copy.unlockCopy
                    trip.connectors[idx].status = .feeding
                }
            }
        }
    }

    // MARK: - Receipts

    private func openReceipts(_ ctx: ReceiptContext) {
        withAnimation(Theme.Motion.overshoot(0.4)) { receiptContext = ctx }
    }

    // MARK: - Page vignette

    /// The `.page` inset glow, redrawn here over this view's opaque paper so the
    /// edges darken slightly instead of reading flat #FFFFFF. CSS `.page
    /// { box-shadow: inset 0 0 80px rgba(20,24,32,0.04) }` — the cool-grey page
    /// ink (#141820) at 4%, strongest at the edges. Matches PageShell's technique
    /// verbatim: an inward-blurred 26pt rounded-rect stroke clipped to the 32pt
    /// page corner, so the band hugs the same card geometry the shell clips this
    /// content to.
    private var pageVignette: some View {
        RoundedRectangle(cornerRadius: Theme.Layout.pageRadius, style: .continuous)
            .stroke(Color(red: 0.08, green: 0.094, blue: 0.125).opacity(0.04), lineWidth: 26)
            .blur(radius: 22)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.pageRadius, style: .continuous))
            .allowsHitTesting(false)
    }
}

// MARK: - Framing word + accent run (teal highlight swash; roman = upright span)

/// CSS `em.accent` highlight band: the gradient is `transparent 64%, rgba(0,137,
/// 168,0.16) 64%→92%, transparent 92%` — i.e. a 28%-tall pale-teal band pinned at
/// 64% down the line box. Shared by the accent run so the swash matches the title's
/// underline-height. Returned as a view so it can back any width of text.
private func framingHighlightBand() -> some View {
    GeometryReader { geo in
        Theme.Palette.teal.opacity(0.16)
            .frame(height: geo.size.height * 0.28)
            .offset(y: geo.size.height * 0.64)
    }
}

/// One plain word in the framing flow. The body is Instrument Serif italic at 21pt
/// (CSS `.brief-open .framing` — `font-family: var(--serif)`, the same face as the
/// "North India." title), matching the reference's narrower glyph advance. `roman`
/// words ("one flight confirmation") use the UPRIGHT serif face (CSS `.roman
/// { font-style:normal }`) instead of italic.
private struct FramingWord: View {
    let word: String
    /// Render upright (Instrument Serif Regular) rather than italic — the CSS
    /// `.roman` exception. Defaults off so callers that don't set it stay italic.
    var roman: Bool = false

    var body: some View {
        Text(word)
            // Regular + italic Instrument Serif share the 27.3pt line box at 21pt,
            // so the roman run drops in without disturbing the flow's row pitch.
            .font(roman ? Theme.Font.serif(21) : Theme.Font.serifItalic(21))
            .tracking(-0.08)                       // CSS letter-spacing -0.004em × 21
            .foregroundStyle(Theme.Palette.ink)
    }
}

/// The accent run ("day 5") rendered as ONE contiguous segment so its highlighter
/// swash is a SINGLE continuous band across the whole phrase — including the inter-
/// word space — matching the CSS `<em class="accent">day 5</em>` (one element), not
/// a per-word block with a gap. `trailing` (e.g. the comma after "5,") sits OUTSIDE
/// the band, hugging it with no flow spacing, exactly as the CSS `<em>` boundary
/// puts the comma outside the highlight. CSS `.accent { padding:0 1px }`.
private struct FramingAccentRun: View {
    let phrase: String
    /// Punctuation that followed the last accent word but is NOT highlighted.
    var trailing: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(phrase)
                .font(Theme.Font.serifItalic(21))
                .tracking(-0.08)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 1)            // CSS `.accent { padding:0 1px }`
                .background(framingHighlightBand())
            if !trailing.isEmpty {
                Text(trailing)
                    .font(Theme.Font.serifItalic(21))
                    .tracking(-0.08)
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
    }
}
