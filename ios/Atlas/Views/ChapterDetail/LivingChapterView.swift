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
        .background(Theme.Palette.paper)
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
            .padding(.top, 70)        // clear the app-mark
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 1 · Masthead / framing

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back affordance (only when embedded under Chapters).
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Chapters").font(Theme.Font.sans(13, weight: .medium))
                    }
                    .foregroundStyle(Theme.Palette.ink3)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
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

            // The italic framing sentence with a teal-highlighted accent — the
            // accent is a BOTTOM-ANCHORED underline marker (lower ~28% of the line),
            // matching CSS `.framing em.accent`, not a full-height block.
            framingView

            // Big serif title.
            Text("\(trip.title).")
                .font(Theme.Font.serifItalic(46))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, 18)

            // Sub-line: dates · stops · day N. Matches `.brief-sub` — the leading
            // date chunk is teal-deep (`.when`), then a 1×9 hairline divider, then
            // the rest in ink-3.
            subLine
                .padding(.top, 4)
        }
    }

    /// The masthead sub-line, split on the first " · " so the date reads teal-deep
    /// (`.brief-sub .when`) with a thin divider before the remainder (`.div`).
    @ViewBuilder
    private var subLine: some View {
        let parts = trip.dateRange.components(separatedBy: " · ")
        HStack(spacing: 8) {
            if let when = parts.first {
                Text(when)
                    .font(Theme.Font.mono(10))
                    .tracking(0.4)
                    .foregroundStyle(Theme.Palette.tealDeep)
                if parts.count > 1 {
                    Rectangle().fill(Theme.Palette.rule).frame(width: 1, height: 9)
                    Text(parts.dropFirst().joined(separator: " · "))
                        .font(Theme.Font.mono(10))
                        .tracking(0.4)
                        .foregroundStyle(Theme.Palette.ink3)
                }
            }
        }
    }

    /// The framing sentence as a wrapping word-flow. Non-accent words are italic
    /// serif `--ink`; the `framingAccent` words are roman serif over a BOTTOM-
    /// ANCHORED teal band (CSS `.framing em.accent`: a highlighter underline filling
    /// the lower ~28% of the line, not a full-height background).
    @ViewBuilder
    private var framingView: some View {
        let accentWords = Set((trip.framingAccent ?? "")
            .split(separator: " ").map(String.init))
        FlowLayout(spacing: 5, lineSpacing: 6) {
            ForEach(Array(framingWords.enumerated()), id: \.offset) { _, word in
                FramingWord(word: word, accent: accentWords.contains(word))
            }
        }
    }

    /// The framing split into words, preserving punctuation as part of each word
    /// so the flow reads naturally.
    private var framingWords: [String] {
        trip.framing.split(separator: " ").map(String.init)
    }

    // MARK: - 2 · The route

    private var routeSection: some View {
        ChapterSection(title: "The route", cite: "how I drew this",
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
        ChapterSection(title: "You’d love, near you") {
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

        // Halo: think → deliver (she reconciled).
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
        // path she returns the rewritten role/unlock copy; adopt it so the row
        // reads what she can now do (the ConnectorsSection already flipped it to
        // "Linked" optimistically via `granted`).
        Task {
            guard let copy = await repo.grantConnector(conn.id) else { return }
            if let idx = trip.connectors.firstIndex(where: { $0.id == conn.id }) {
                withAnimation(Theme.Motion.standard(0.3)) {
                    trip.connectors[idx].role = copy.role
                    // The post-grant role the row shows is `grantedRole`; adopt the
                    // server's authoritative "what she can now do" copy there too.
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
}

// MARK: - Framing word (accent = bottom-anchored teal underline marker)

/// One word in the framing flow. Accent words are roman serif over a teal band
/// occupying the lower ~28% of the line height (CSS `.framing em.accent`), drawn
/// behind the glyphs so it reads as a highlighter underline, not a full block.
private struct FramingWord: View {
    let word: String
    let accent: Bool

    var body: some View {
        Text(word)
            .font(accent
                  ? .custom(Theme.Typeface.serifRegular, size: 21)
                  : .custom(Theme.Typeface.serifItalic, size: 21))
            .foregroundStyle(Theme.Palette.ink)
            .background(alignment: .bottom) {
                if accent {
                    GeometryReader { geo in
                        Theme.Palette.teal.opacity(0.16)
                            .frame(height: geo.size.height * 0.28)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
    }
}
