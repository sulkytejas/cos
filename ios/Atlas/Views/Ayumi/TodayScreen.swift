import SwiftUI
import SwiftData

/// Today — the conversational home. One scrolling thread between the user and
/// Ayumi (italic-serif voice, roman user bubbles), with embedded brief/action
/// capsules that morph into letters, and a fixed compose bar.
///
/// v1 (Today agentic flow): the thread is no longer a hardcoded script — it is
/// the live `turns` table, mirrored from the server's nightly daily-scan. The
/// VERDICT (a morning turn's `body`) is what shows here; the full redlineable
/// MEMO lives in Review. Every visual primitive below (AyumiTurn / UserTurn /
/// ThinkingLine / BriefCapsule / DayDivider geometry, the EOLayer, the
/// `--today-bottom` debug hook, the 70px conv inset) is unchanged — only the
/// DATA SOURCE moved from literals to `@Query`, plus the new review chip and
/// connector line that the morning turn can carry.
struct TodayScreen: View {
    @Environment(HaloController.self) private var halo
    @Environment(NavRouter.self) private var router
    /// The single SwiftData writer / API pass-through — the CONNECT sheet reads a
    /// source's `connectorStatus` and mints its `connectorAuthURL` through this.
    @Environment(AtlasRepo.self) private var repo
    @State private var rings: [EORingItem] = []

    /// The morning turn's connector line presents an in-place CONNECT SHEET — the
    /// SAME generic sheet for any supported source (gmail | calendar | drive).
    /// Tapping no longer routes anywhere; the sheet runs the real Google OAuth
    /// round-trip when the server is configured, or the app-wide demo grant when
    /// it isn't. `connectSheetSource` holds the source being connected (drives the
    /// `.sheet` presentation); `fedSources` records which sources have flipped to
    /// FEEDING so the line's trailing CTA reads "{SOURCE} · FEEDING" thereafter.
    @State private var connectSheetSource: ConnectSheetItem? = nil
    @State private var fedSources: Set<String> = []

    /// The whole thread, oldest → newest (the morning turn first, the night's
    /// exchange below it), mirrored from `turns`.
    @Query(sort: \Turn.createdAt, order: .forward) private var turns: [Turn]
    /// Live pending proposals — only their COUNT is read, for the review chip's
    /// "{n} waiting for you" label (the same `status == "pending"` predicate
    /// Review filters on).
    @Query(filter: #Predicate<Proposal> { $0.statusRaw == "pending" })
    private var pendingProposals: [Proposal]
    /// All briefs — used to resolve a turn's `briefIds` to a `Brief` for the
    /// embedded capsule (title + when).
    @Query private var briefs: [Brief]

    private let space = "today.scroll"

    /// DEBUG: `--today-bottom` opens the thread scrolled to the foot (for shooting
    /// the bottom of the screen against the mock).
    private var scrollBottomDebug: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--today-bottom")
        #else
        false
        #endif
    }

    /// DEBUG: `--connector-sheet` auto-presents the in-place CONNECT sheet on
    /// appear (using the morning turn's connector) so the sheet can be shot
    /// against the design without a tap. Same convention as `--today-bottom`.
    private var connectorSheetDebug: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--connector-sheet")
        #else
        false
        #endif
    }

    /// The newest morning turn — its overnight `window` drives the "while you
    /// slept" divider, and it is the turn that may carry the review chip +
    /// connector line.
    private var morningTurn: Turn? {
        turns.last { $0.kind == .morning }
    }

    /// Live pending count for the review chip ("{n} waiting for you").
    private var pendingCount: Int { pendingProposals.count }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The "while you slept" divider is the first conv element. Its
                    // clearance from the app-mark comes entirely from the conv's
                    // 70px top inset (set below) + the divider's own 14px top
                    // margin — matching CSS, no extra top pad here. Its window is
                    // the newest morning turn's overnight [start, end]; the
                    // hardcoded "02:14 → 06:38" is the fallback when no morning
                    // turn (or its window) is present.
                    DayDivider(label: "while you slept", roman: sleptWindow)

                    if turns.isEmpty {
                        // Empty state: Ayumi hasn't written the first morning yet
                        // (no scan has run). One quiet italic line, in the same
                        // AyumiTurn frame the real morning will occupy.
                        AyumiTurn(when: "",
                                  paragraphs: [ayumiProse([.init("Nothing yet — I'll write you after tonight.")], size: 17)])
                    } else {
                        ForEach(turns) { turn in
                            turnView(turn)
                        }
                    }

                    DayDivider(label: "now", roman: Self.clock(Date()))
                    Spacer().frame(height: 16)   // CSS .conv padding-bottom 16
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)                // CSS .conv padding-top 6
            }
            .coordinateSpace(name: space)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(scrollBottomDebug ? .bottom : .top)
            // The page already sits below the Dynamic Island (PageShell insets it
            // within the safe area). Without this the ScrollView ADDS the safe-area
            // inset a second time, pushing the whole thread ~59px down — the "huge"
            // top gap.
            .ignoresSafeArea(.container, edges: .top)
            // CSS `.conv { inset: 70px 0 60px 0 }` — the scroll viewport is inset
            // inside the page, which itself sits `var(--halo-inset)=22px` below the
            // physical top. Because `.ignoresSafeArea(.top)` measures this padding
            // from the PHYSICAL top (not the page), the conv top inset is the SUM:
            // page-top(22) + conv-inset(70) = 92. But the divider's own clearance
            // ALSO comes from the VStack top pad (6) + DayDivider's vpad (14) on top
            // of that — so 92 here placed the first "while you slept" divider ~18pt
            // too low. The earlier haloInset+52 = 74 over-corrected the OTHER way:
            // the "while you slept" divider (and the whole feed below it) sat ~3.5pt
            // too LOW vs the ref, accumulating into a ~9pt drift at the bottom cue.
            // haloInset+48 = 70 lands on the CSS `.conv` inset exactly and lifts the
            // divider ~4pt to match the ref, while still clearing the app-mark
            // (which the shell pins at haloInset+30=52pt).
            .padding(.top, Theme.Layout.haloInset + 48)   // 22 + 48 = 70 (CSS .conv inset)
            .padding(.bottom, 60)

            // v0.7: the bottom compose pill was removed — it was redundant with
            // the global Capture cue (mounted in PageShell). Today now reaches
            // Ayumi the same way every other screen does: summon in place.
            EOLayer(rings: rings)
        }
        // The in-place CONNECT sheet — presented by the connector line's tap, the
        // same generic surface for gmail | calendar | drive. On a granted outcome
        // it records the source in `fedSources`, flipping the line to FEEDING.
        .sheet(item: $connectSheetSource) { item in
            ConnectorSheet(connector: item.connector,
                           repo: repo,
                           onGranted: {
                               withAnimation(Theme.Motion.overshoot()) {
                                   _ = fedSources.insert(item.connector.source)
                               }
                           })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        // DEBUG hook: auto-open the CONNECT sheet on appear for screenshotting it
        // against the design (no tap available without idb). Picks the morning
        // turn's connector if it carries a grantable one.
        .task {
            guard connectorSheetDebug, connectSheetSource == nil,
                  let connector = morningTurn?.connector,
                  Self.grantableSources.contains(connector.source) else { return }
            connectSheetSource = ConnectSheetItem(connector: connector)
        }
    }

    // ─── Capture ──────────────────────────────────────────────────
    // The bottom compose pill was retired in v0.7. Capturing a thought is now
    // global: summon Ayumi in place from the cue at the foot of every screen
    // (PageShell → CaptureHost). This screen keeps only its reading thread.

    private func emitRing() {
        let item = EORingItem(point: CGPoint(x: 200, y: 560))
        rings.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            rings.removeAll { $0.id == item.id }
        }
    }

    // ─── Thread rendering (data-driven) ───────────────────────────
    // The thread is `turns`, oldest→newest. Each turn maps onto exactly one of
    // the existing visual primitives by role+kind:
    //   • user                 → UserTurn (roman bubble, right-aligned)
    //   • ayumi · thinking      → AyumiTurn(thinking:) (the jade-dot reasoning line)
    //   • ayumi · morning/message → AyumiTurn(paragraphs:source:) with capsule embeds
    // The morning turn additionally carries the review chip + connector line.

    @ViewBuilder
    private func turnView(_ turn: Turn) -> some View {
        switch (turn.role, turn.kind) {
        case (.user, _):
            UserTurn(text: turn.body, when: Self.clock(turn.createdAt))

        case (.ayumi, .thinking):
            // The thinking line lives inside an AyumiTurn (so the avatar/rail +
            // "Ayumi HH:mm" header come from the shared frame); the jade dot sits
            // in the prose column, exactly as the prior scripted turn rendered.
            AyumiTurn(when: Self.clock(turn.createdAt), thinking: turn.body)

        case (.ayumi, _):
            // Ayumi's verdict (morning) or a plain message. The body is parsed
            // through the shared Ayumi-markup grammar (paragraphs on "\n\n";
            // *roman*; ==accent==) and each paragraph becomes one `ayumiProse`
            // Text at the canonical 17pt prose size.
            let paragraphs = parseAyumiMarkup(turn.body).map { ayumiProse($0, size: 17) }
            let isMorning = turn.kind == .morning
            AyumiTurn(when: Self.clock(turn.createdAt),
                      paragraphs: paragraphs,
                      source: turn.sourceTag) {
                // The capsules this turn references, then — on the morning turn
                // only — the review chip and (if present) the connector line.
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(turn.briefIds, id: \.self) { briefId in
                        if let brief = brief(briefId) {
                            capsule(for: brief)
                        }
                    }
                    if isMorning {
                        if pendingCount > 0 { reviewChip }
                        // Render the connector line ONLY for a source the in-place
                        // CONNECT sheet can actually grant (gmail | calendar |
                        // drive — the server's OAuth `z.enum`). The worker may name
                        // any source she observes a gap for; an UNSUPPORTED one
                        // (e.g. "whatsapp") is never shown as a CTA — it is logged
                        // server-side to the dev wishlist instead, so the line never
                        // makes a promise the sheet can't keep.
                        //
                        // NEWEST morning only: consecutive unconnected mornings each
                        // persist the same suggestion on their turn row; rendering
                        // every one would stack identical CONNECT CTAs down the
                        // thread. Her ask appears once, on the latest morning.
                        if turn.id == morningTurn?.id,
                           let connector = turn.connector, Self.grantableSources.contains(connector.source) {
                            connectorLine(connector)
                        }
                    }
                }
            }
        }
    }

    /// Resolve a referenced brief id to its `Brief` (nil if the brief hasn't
    /// synced yet — its capsule is simply skipped).
    private func brief(_ id: UUID) -> Brief? {
        briefs.first { $0.id == id }
    }

    /// The embedded brief capsule (collapsed pill → unfurling letter). The Karan
    /// brief (which has a person/prediction/tactical structure) opens its full
    /// letter and offers "OPEN FULL BRIEF →" → the Brief screen; capsules with no
    /// recognisable structure fall back to the brief's preview line.
    private func capsule(for brief: Brief) -> some View {
        BriefCapsule(brief: brief,
                     onOpen: { emitRing(); halo.setState(.delivered) },
                     onOpenFull: { withAnimation(Theme.Motion.overshoot()) { router.go(.brief) } })
    }

    // ─── Review chip ──────────────────────────────────────────────
    /// A quiet pill in the thread column under the morning turn's capsules:
    /// "{n} waiting for you   memo →" → the Review redline. Styled like the
    /// collapsed BriefCapsule (card fill + shadow1, mono 9.5 meta) but visually
    /// quieter — no glyph square, teal-deep mono text. Hidden when n == 0 (the
    /// call site already guards on `pendingCount > 0`).
    private var reviewChip: some View {
        Button {
            withAnimation(Theme.Motion.overshoot()) { router.go(.review) }
        } label: {
            HStack(spacing: 10) {
                Text("\(pendingCount) waiting for you")
                    .font(Theme.Font.mono(9.5)).tracking(0.4)
                    .foregroundStyle(Theme.Palette.tealDeep)
                Spacer(minLength: 12)
                Text("memo →")
                    .font(Theme.Font.mono(9.5)).tracking(0.4)
                    .foregroundStyle(Theme.Palette.tealDeep)
            }
            // Match the collapsed capsule's padding so the chip reads as a sibling
            // pill, just without the leading glyph square.
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 999, style: .continuous).fill(Theme.Palette.card))
            .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
            .shadow1()
        }
        .buttonStyle(.plain)
    }

    // ─── Connector line ───────────────────────────────────────────
    /// The connector sources the in-place CONNECT sheet can grant — the server's
    /// OAuth `z.enum(["gmail","calendar","drive"])` (§4.f Phase 5). All three are
    /// honored directly now: the sheet runs the same generic flow for each, so
    /// there is no destination that lacks a row. Any source OUTSIDE this set is
    /// never rendered as a CTA (suppressed at the call site).
    private static let grantableSources: Set<String> = ["gmail", "calendar", "drive"]

    /// The morning turn's single connector suggestion: a src-tag-style row of
    /// small italic-serif copy + a mono affordance in teal-deep. Once the source
    /// has flipped to FEEDING (granted in the sheet, OR found already-active on a
    /// fresh-visit status check), the trailing line becomes a NON-tappable
    /// "{SOURCE} · FEEDING" and the whole row stops acting as a button; otherwise
    /// it reads "CONNECT {SOURCE} →" and tapping presents the in-place sheet (no
    /// navigation). On appear — when the backend is configured — we check the
    /// source's status once so a previously-granted source renders FEEDING
    /// immediately rather than re-offering CONNECT.
    @ViewBuilder
    private func connectorLine(_ connector: TurnConnector) -> some View {
        let fed = fedSources.contains(connector.source)
        Group {
            if fed {
                // Granted — a quiet, non-tappable state. The subject is HER world
                // ("She can see it now."), never the machinery.
                VStack(alignment: .leading, spacing: 6) {
                    Text(connector.copy)
                        .font(Theme.Font.serifItalic(14.5))
                        .foregroundStyle(Theme.Palette.ink2)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Text("\(connector.source.uppercased()) · FEEDING")
                        .font(Theme.Font.mono(9.5)).tracking(1.0)
                        .foregroundStyle(Theme.Palette.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    connectSheetSource = ConnectSheetItem(connector: connector)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(connector.copy)
                            .font(Theme.Font.serifItalic(14.5))
                            .foregroundStyle(Theme.Palette.ink2)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Text("CONNECT \(connector.source.uppercased()) →")
                            .font(Theme.Font.mono(9.5)).tracking(1.0)
                            .foregroundStyle(Theme.Palette.tealDeep)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // Fresh-visit reconcile: if the backend is configured and the source is
        // ALREADY active server-side (granted on a prior session), render FEEDING
        // without making the user re-tap. nil/unsupported/offline → leave the CTA.
        .task(id: connector.source) {
            guard !fedSources.contains(connector.source),
                  await repo.isConnectorBackendConfigured else { return }
            if let status = await repo.connectorStatus(source: connector.source),
               status.status == "active" {
                withAnimation(Theme.Motion.overshoot()) {
                    _ = fedSources.insert(connector.source)
                }
            }
        }
    }

    // ─── Time helpers ─────────────────────────────────────────────

    /// "HH:mm" for the "while you slept" window, from the newest morning turn's
    /// overnight `window`; the design's canonical "02:14 → 06:38" is the fallback
    /// (no morning turn yet, or one without a window).
    private var sleptWindow: String {
        guard let w = morningTurn?.window else { return "02:14 → 06:38" }
        return "\(Self.clock(w.start)) → \(Self.clock(w.end))"
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    static func clock(_ d: Date) -> String { clockFormatter.string(from: d) }
}

// MARK: - Ayumi turn

private struct AyumiTurn<Embed: View>: View {
    let when: String
    var paragraphs: [Text] = []
    var source: String? = nil
    var thinking: String? = nil
    @ViewBuilder var embed: () -> Embed

    init(when: String, paragraphs: [Text] = [], source: String? = nil, thinking: String? = nil,
         @ViewBuilder embed: @escaping () -> Embed = { EmptyView() }) {
        self.when = when; self.paragraphs = paragraphs; self.source = source
        self.thinking = thinking; self.embed = embed
    }

    var body: some View {
        // CSS: `.turn { padding: 10px 0 14px 18px }` — 18px left gutter = the
        // 12px avatar/thread column + 6px spacing.
        HStack(alignment: .top, spacing: 6) {
            // thread line + avatar. CSS `.turn.ayumi::before { width: 1px;
            // background: linear-gradient(#00576B 0%, rgba(40,44,52,.1) 100%) }`:
            // the rail starts FULL-strength deep teal at the avatar (reading like
            // an inked stroke) and dissolves to a 10% neutral-ink whisper at its
            // foot — not the teal→teal fade a previous pass used, which kept the
            // foot tinted and lost the stroke-like top.
            VStack(spacing: 6) {
                AyumiAvatar(size: 12)
                Rectangle()
                    .fill(LinearGradient(colors: [Color(hex: 0x00576B), Color(hex: 0x282C34).opacity(0.10)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Ayumi").font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink)
                    Text(when).font(Theme.Font.mono(9.5)).tracking(0.6).foregroundStyle(Theme.Palette.ink3)
                }
                .padding(.bottom, 8)   // .turn-meta { margin-bottom: 8px }

                // CSS: `.body { font-size:17px; line-height:1.46 }`, paragraphs
                // separated by `p + p { margin-top: 8px }` (NOT a blank line).
                // Instrument Serif's natural line height at 17pt is ~22.1pt, so the
                // CSS pitch of 17×1.46≈24.8pt needs lineSpacing ≈ 24.8−22.1 = 2.7pt.
                // The prior `lineSpacing(4)` rendered ~26.1pt pitch (~1.3pt too tall
                // per line), which loosened the prose and pushed the whole feed down.
                // Paragraph gap: CSS adds the 8px margin between 24.82px line
                // BOXES (text + half-leading each side); SwiftUI stacks the font's
                // NATURAL bounds (~22.1pt), so the 2.7pt of leading evaporates at
                // every boundary. spacing = 8 + 2.7 ≈ 10.7 restores the CSS pitch
                // (measured: ref 33.3pt baseline-to-baseline across the break,
                // sim was 29.3pt at spacing 8).
                if !paragraphs.isEmpty {
                    VStack(alignment: .leading, spacing: 10.7) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                            p.lineSpacing(2.7).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // The thinking line sits in the prose column (green-dot bullet),
                // not at content-left — it reads as Ayumi reasoning aloud.
                if let thinking {
                    ThinkingLine(text: thinking)
                }

                if let source {
                    Text(source)
                        .font(Theme.Font.mono(9))   // .src-tag { font-size: 9px }
                        .tracking(0.54)             // 0.06em × 9px
                        .foregroundStyle(Theme.Palette.ink4)
                        .padding(.top, 8)   // .src-tag { margin-top: 8px }
                }

                embed().padding(.top, 12)   // .ssatom { margin-top: 12px }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

/// The green-dot "thinking" bullet. Rendered inside an `AyumiTurn` prose column
/// (the avatar/thread gutter + "Ayumi 07:15" header come from the parent), so the
/// dot sits indented under the prose — matching the mock — not at content-left.
private struct ThinkingLine: View {
    let text: String
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Theme.Palette.jade)
                .frame(width: 7, height: 7)
                // CSS .thinking-pulse::after { inset:-4px } — a soft jade halo
                // (radial 0.45→0 at 70%) breathing in sync with the dot.
                .background(
                    Circle()
                        .fill(RadialGradient(colors: [Theme.Palette.jade.opacity(0.45), Theme.Palette.jade.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: 7.5))
                        .frame(width: 15, height: 15)
                )
                .scaleEffect(on ? 1.18 : 1.0)
                .opacity(on ? 1 : 0.55)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
            Text(text)
                .font(Theme.Font.serifItalic(14.5))
                .foregroundStyle(Theme.Palette.ink2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

// MARK: - User turn

private struct UserTurn: View {
    let text: String
    let when: String
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Text(when).font(Theme.Font.mono(9.5)).tracking(0.6).foregroundStyle(Theme.Palette.ink3)
                Text("YOU").font(Theme.Font.mono(9.5)).tracking(1.5).foregroundStyle(Theme.Palette.ink3)
            }
            Text(text)
                // CSS .turn.user .bubble { font-family: var(--sans)=Manrope; font-size: 14.5px }.
                // Reference the Manrope FAMILY name directly rather than the
                // `Manrope-Regular` named-instance PS name: on the iOS sim the
                // bundled variable font does NOT expose the fvar instance PS
                // names, so `.custom("Manrope-Regular")` (what `Theme.Font.sans`
                // resolves to) silently falls back to the system sans — a WIDER
                // face that wraps line 1 one word early ("…I" instead of
                // "…I should"). The family name resolves to Manrope's Regular
                // default and renders at the correct (narrower) advance.
                .font(.custom(Theme.Typeface.sansFamily, size: 14.5))
                .tracking(0)                   // default/zero tracking — CSS sets none
                .foregroundStyle(.white)
                // CSS `line-height: 1.4` at 14.5px ≈ 20.3pt line pitch. Manrope's
                // natural pitch at 14.5pt is already ≈1.4, so add no extra leading
                // (the prior `lineSpacing(3)` loosened it to ~1.6 → bubble too tall).
                .lineSpacing(0)
                // Lay the text out at a fixed text width so it wraps exactly like
                // the design ("…anything else I should / know before the call?").
                // CSS caps the bubble at `max-width: 78%`; on-device the conv content
                // width measures ~305pt, so the bubble maxes at 0.78×305 ≈ 238pt and
                // the text window is 238 − 28pt h-padding ≈ 210pt. The ref renders the
                // bubble exactly at this cap (L=111pt, R=349pt, W=238pt) with line 1
                // "…anything else I should" reaching the full width. The prior 220pt
                // overshot it by ~10pt, pushing line 1 past the ref's right edge.
                .frame(width: 210, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                           bottomTrailingRadius: 4, topTrailingRadius: 18, style: .continuous)
                        .fill(Theme.Palette.ink)
                )
                .shadow1()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 10)
    }
}

// MARK: - Brief capsule (morphs to a letter)

private struct BriefCapsule: View {
    /// The brief this capsule embeds — title + when come from it, and the
    /// unfurled letter renders generically from its `structureData`.
    let brief: Brief
    let onOpen: () -> Void
    var onOpenFull: () -> Void = {}
    @State private var open = false

    /// Collapsed pill title — the brief's own title.
    private var title: String { brief.title }
    /// Collapsed pill trailing time — the brief's `when` ("today · 5 min" → "5 min").
    private var when: String { brief.when ?? "" }

    /// Decode the brief's sections once (nil → the letter falls back to preview).
    private var sections: [BriefSection] {
        (try? JSONDecoder().decode(BriefStructure.self, from: brief.structureData))?.sections ?? []
    }

    var body: some View {
        Group {
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow(stretch: true)
                    letter.transition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Collapsed: hug short titles (like the mock), but never exceed the
                // thread column. A long live title caps to the available width and
                // truncates instead of forcing the whole screen wider — that
                // intrinsic overflow is what was centering/clipping all of Today.
                ViewThatFits(in: .horizontal) {
                    headerRow(stretch: false)
                    headerRow(stretch: true).frame(maxWidth: .infinity)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: open ? 8 : 999, style: .continuous).fill(Theme.Palette.card)
        )
        .clipShape(RoundedRectangle(cornerRadius: open ? 8 : 999, style: .continuous))
        .shadow1()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Theme.Motion.overshootStrong(0.55)) { open.toggle() }
            if open { onOpen() }
        }
    }

    /// The pill / letter head row. `stretch` pushes time+chevron to the far edge
    /// (used when the capsule fills its column); otherwise the row hugs content.
    private func headerRow(stretch: Bool) -> some View {
        let meta = Self.shortWhen(when)
        // The cap-glyph is a plain obsidian square with a single catchlight —
        // no initial inside (matches the mock).
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.Palette.ink)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(RadialGradient(colors: [Theme.Palette.avatarInk.opacity(0.55), .clear],
                                             center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: 11))
                )
                .frame(width: 18, height: 18)

            // Title fills (and truncates) when the capsule stretches; the short
            // time meta keeps its intrinsic width so it always stays readable.
            // Collapsed, the row hugs its content (CSS `width: fit-content`): the
            // only gap between label and time is the HStack's 10pt spacing, which
            // matches CSS `.atom-capsule { gap: 10px }`. An earlier extra 12pt
            // spacer here doubled that gap and stretched the pill ~22pt too wide.
            Text(title).font(Theme.Font.serifItalic(15)).foregroundStyle(Theme.Palette.ink)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: stretch ? .infinity : nil, alignment: .leading)
            if !meta.isEmpty {
                Text(meta).font(Theme.Font.mono(9.5)).tracking(0.4).foregroundStyle(Theme.Palette.tealDeep)
                    .lineLimit(1).fixedSize()
            }
        }
        // Capsule: padding 8px 12px 8px 16px (the mock hugs its content and
        // shows no chevron — open is signalled by the letter unfurling).
        .padding(.vertical, 8)
        .padding(.leading, 16)
        .padding(.trailing, 12)
    }

    /// The live `when` is "today · X"; everything is "today", so drop that
    /// redundant prefix and keep the meaningful tail (a time or short label) so
    /// the title gets the room — matching the mock's short trailing time.
    static func shortWhen(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        let lower = t.lowercased()
        for p in ["today · ", "today·", "today - ", "today "] where lower.hasPrefix(p) {
            t = String(t.dropFirst(p.count)); break
        }
        return t.lowercased() == "today" ? "" : t.trimmingCharacters(in: .whitespaces)
    }

    /// The unfurled letter — rendered GENERICALLY from the brief's structure,
    /// keeping the exact visual idiom the scripted Karan letter used:
    ///   • a `person` section → the "PERSON" label + a name·role row;
    ///   • a `prediction` section → "LIKELY TO COME UP" + a confidence row per
    ///     item (high→.94 / medium→.55 / low→.31, matching the prior pills);
    ///   • a `tactical` section → "OPEN WITH" + its text;
    /// When the brief carries none of these (the churn-swap capsule, say), fall
    /// back to the brief's `preview` as a single row so the letter is never empty.
    @ViewBuilder
    private var letter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.Palette.rule).frame(height: 1)   // border-top 1px

            if hasLetterBody {
                if let person = personSection {
                    label("Person")
                    row("\(person.name) · \(person.role)")
                }
                if let prediction = predictionSection {
                    label("Likely to come up")
                    ForEach(prediction.items) { item in
                        confRow(Self.confidenceValue(item.confidence), item.text)
                    }
                }
                if let tactical = tacticalSection {
                    label("Open with")
                    row(tactical.text)
                }
            } else if let preview = brief.preview, !preview.isEmpty {
                // No recognisable sections — show the brief's one-line preview so
                // the unfurled card still says something.
                row(preview)
            }

            Button { onOpenFull() } label: {
                Text("OPEN FULL BRIEF →")
                    .font(Theme.Font.mono(10)).tracking(1.2)
                    .foregroundStyle(Theme.Palette.tealDeep)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) {        // border-bottom 1px teal
                        Rectangle().fill(Theme.Palette.tealDeep.opacity(0.3)).frame(height: 1)
                    }
                    .padding(.top, 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    /// True when the brief has at least one of the three letter sections.
    private var hasLetterBody: Bool {
        personSection != nil || predictionSection != nil || tacticalSection != nil
    }
    private var personSection: PersonData? {
        for s in sections { if case .person(let d) = s { return d } }
        return nil
    }
    private var predictionSection: PredictionData? {
        for s in sections { if case .prediction(let d) = s { return d } }
        return nil
    }
    private var tacticalSection: TacticalData? {
        for s in sections { if case .tactical(let d) = s { return d } }
        return nil
    }

    /// Map a prediction confidence onto the canonical pill values the scripted
    /// Karan letter used (high .94 / medium .55 / low .31).
    static func confidenceValue(_ c: PredictionData.Item.Confidence) -> Double {
        switch c { case .high: 0.94; case .medium: 0.55; case .low: 0.31 }
    }

    private func label(_ s: String) -> some View {
        Text(s.uppercased()).font(Theme.Font.mono(9.5)).tracking(1.5)
            .foregroundStyle(Theme.Palette.ink3).padding(.top, 14).padding(.bottom, 2)
    }
    private func row(_ s: String) -> some View {
        Text(s).font(Theme.Font.serifItalic(14.5)).foregroundStyle(Theme.Palette.ink2)
            .lineSpacing(4).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
    }
    private func confRow(_ v: Double, _ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ConfidencePill(value: v)
            Text(s).font(Theme.Font.serifItalic(14.5)).foregroundStyle(Theme.Palette.ink)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1) }
    }
}

// MARK: - Connect sheet

/// Identifiable wrapper so the connector suggestion can drive `.sheet(item:)`
/// (the model `TurnConnector` is Codable-only; the source string is a stable id —
/// a turn carries at most one connector, so it can't collide within a screen).
private struct ConnectSheetItem: Identifiable {
    let connector: TurnConnector
    var id: String { connector.source }
}

/// The in-place CONNECT sheet — ONE generic surface for any supported source
/// (gmail | calendar | drive). Presented by the morning turn's connector line in
/// place of the old route to North India. It mirrors the memo-card idiom: a paper
/// card, a small letter-spaced mono header, and serif-italic prose whose subject
/// is HER world, never the machinery.
///
/// The sheet picks its path from whether the backend is reachable:
///   • configured (.server + https + token): the REAL Google OAuth round-trip —
///     mint a consent URL, open it, then poll `connectorStatus` to "active";
///   • unconfigured / .local: the app-wide DEMO grant — a short delay, then FED
///     (everything in the local store is demo data).
private struct ConnectorSheet: View {
    let connector: TurnConnector
    let repo: AtlasRepo
    /// Called once the source has flipped to FEEDING, so the caller can record it
    /// and re-render the connector line as non-tappable.
    let onGranted: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    /// The states the sheet can be in:
    ///   • idle        — the CONNECT button is offered (initial / after status read);
    ///   • connecting  — the consent URL is opening and we're polling for "active",
    ///     OR the demo delay is running;
    ///   • fed         — the grant is live; the quiet "{SOURCE} · FEEDING" state,
    ///     no button (reached via the button OR an on-appear already-active read);
    ///   • unreachable — the server can't reach Google (authUrl threw
    ///     PRECONDITION_FAILED); a single quiet line, no retry.
    private enum Phase { case idle, connecting, fed, unreachable }
    @State private var phase: Phase = .idle
    /// The in-flight connect (URL mint + status poll, or the demo delay), held so
    /// it is cancelled on disappear — the bounded poll must not outlive the sheet.
    @State private var connectTask: Task<Void, Never>? = nil

    private var source: String { connector.source }
    private var SOURCE: String { connector.source.uppercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — mono, small, letter-spaced; the machinery named only here.
            Text("CONNECT — \(SOURCE)")
                .font(Theme.Font.mono(9.5)).tracking(1.5)
                .foregroundStyle(Theme.Palette.ink3)
                .padding(.bottom, 14)

            // Her copy — the suggestion's prose, parsed through the shared Ayumi
            // grammar so *roman*/==accent== runs render exactly as elsewhere.
            VStack(alignment: .leading, spacing: 10.7) {
                ForEach(Array(parseAyumiMarkup(connector.copy).enumerated()), id: \.offset) { _, runs in
                    ayumiProse(runs, size: 16)
                        .lineSpacing(2.7).fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 24)

            // The phase-driven foot: button / progress / fed line / unreachable.
            switch phase {
            case .idle:
                // Title-case the display name — the raw enum value is lowercase
                // ("calendar"), and "Connect calendar" reads broken on the pill.
                PillButton(title: "Connect \(source.capitalized)", kind: .primary) { connect() }
            case .connecting:
                HStack(spacing: 10) {
                    ProgressView()
                    // Quiet, worldly — never OAuth vocabulary ("the grant") as the
                    // subject of a rendered line.
                    Text("One moment…")
                        .font(Theme.Font.serifItalic(14.5))
                        .foregroundStyle(Theme.Palette.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 13)
            case .fed:
                fedState
            case .unreachable:
                Text("I can't reach it yet — nothing for you to do.")
                    .font(Theme.Font.serifItalic(14.5))
                    .foregroundStyle(Theme.Palette.ink2)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // A quiet plain dismiss — mono, ink3 — hidden once fed (the FED state
            // is terminal; she closes via the drag indicator).
            if phase != .fed {
                Button { dismiss() } label: {
                    Text("not now")
                        .font(Theme.Font.mono(9.5)).tracking(1.0)
                        .foregroundStyle(Theme.Palette.ink3)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.paper)
        // On appear: if configured and already active, open straight into FED.
        .task { await checkExistingStatus() }
        // The bounded poll must not outlive the sheet — cancel it on disappear.
        .onDisappear { connectTask?.cancel() }
    }

    /// The granted state — quiet mono tag + a serif-italic line about HER world.
    private var fedState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(SOURCE) · FEEDING")
                .font(Theme.Font.mono(9.5)).tracking(1.0)
                .foregroundStyle(Theme.Palette.ink3)
            Text("Now I'll bring you what matters from it.")
                .font(Theme.Font.serifItalic(15))
                .foregroundStyle(Theme.Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─── Flow ─────────────────────────────────────────────────────

    /// On appear, surface FED immediately if the source is already granted
    /// server-side (so a re-open after a prior grant doesn't re-offer CONNECT).
    private func checkExistingStatus() async {
        guard phase == .idle, await repo.isConnectorBackendConfigured else { return }
        if let status = await repo.connectorStatus(source: source), status.status == "active" {
            phase = .fed
            onGranted()
        }
    }

    /// CONNECT tapped. Configured → the real OAuth round-trip; otherwise the demo
    /// grant. Both terminate in FED (or, for the real path, `unreachable` when the
    /// server has no Google credentials).
    private func connect() {
        connectTask?.cancel()
        connectTask = Task {
            if await repo.isConnectorBackendConfigured {
                await connectServer()
            } else {
                await connectDemo()
            }
        }
    }

    /// Real path: mint + open the consent URL, then poll status to "active". A
    /// thrown authUrl (PRECONDITION_FAILED — OAuth not configured) drops to the
    /// quiet `unreachable` state with no retry.
    private func connectServer() async {
        let url: URL
        do {
            url = try await repo.connectorAuthURL(source: source)
        } catch {
            phase = .unreachable
            return
        }
        phase = .connecting
        openURL(url)
        // Poll every 2s, bounded ~120s. The view's `.task` is cancelled on
        // disappear, so this loop unwinds if she closes the sheet mid-grant.
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            if let status = await repo.connectorStatus(source: source), status.status == "active" {
                withAnimation(Theme.Motion.overshoot()) { phase = .fed }
                onGranted()
                return
            }
        }
        // Timed out without a grant — fall back to the button so she can retry.
        phase = .idle
    }

    /// Demo path (unconfigured / .local): everything in the local store is demo
    /// data, so simulate the grant after a short beat, then FED.
    private func connectDemo() async {
        phase = .connecting
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        if Task.isCancelled { return }
        withAnimation(Theme.Motion.overshoot()) { phase = .fed }
        onGranted()
    }
}
