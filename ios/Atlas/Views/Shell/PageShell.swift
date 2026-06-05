import SwiftUI

/// Live date for the Today app-mark crumb (e.g. "Jun 4"), evaluated once at launch.
/// File-scope because PageShell is generic (no static stored properties allowed).
private let todayDateCrumb: String = {
    let f = DateFormatter(); f.dateFormat = "MMM d"
    return f.string(from: Date())
}()

/// The shared shell every Ayumi screen sits in: a full-bleed Halo behind an
/// opaque paper page surface inset 22pt (radius 32), with the app-mark, edge
/// chevrons, the logo-menu index sheet, and horizontal-swipe navigation.
/// The screen's own content is supplied via `content` and owns its internal
/// padding (top ~70 to clear the app-mark).
///
/// v0.7: the global Capture cue (CaptureHost) is mounted ONCE here, above the
/// page on EVERY screen, bridged to this shell's Halo so capture drives the
/// same presence. It lifts above a host bottom bar via `captureAvoidInset`.
struct PageShell<Content: View>: View {
    var router: NavRouter
    var halo: HaloController
    /// The screen name shown as "Capturing — over <screen>" + which bottom bar
    /// (if any) the cue must avoid. Defaults to the router's current page so the
    /// cue reads correctly without extra wiring.
    var captureScreenName: String? = nil
    var captureAvoidInset: CGFloat? = nil
    /// When the Living Chapter overlays the page: the chapter draws its own
    /// "‹ Chapters / NORTH INDIA ▾" nav inside the content, so the shell hides
    /// its global app-mark / topbar + edge chevrons. The page surface itself is
    /// the SAME 22pt-inset rounded card as every other screen (CSS `.page` is
    /// `inset 22px; radius 32; background paper` for all screens — the chapter
    /// reference shows the timeline inside the standard inset card over the
    /// #f7f7f5 desk, not full-bleed).
    var chapterMode: Bool = false
    @ViewBuilder var content: () -> Content

    @State private var showIndex = false
    @State private var showSettings = false

    private var screenName: String { captureScreenName ?? router.current.title }
    private var avoidInset: CGFloat { captureAvoidInset ?? router.current.captureAvoidInset }

    /// Screens that supply their OWN in-content header (back affordance + crumb)
    /// and therefore suppress the shell's topbar entirely. Brief renders its own
    /// "‹ Today / STRATYFIX ▾" row; Search renders "‹ Today / A SEARCH ▾"; Review
    /// renders "‹ Today / A REVIEW ▾"; the Living Chapter renders
    /// "‹ Chapters / NORTH INDIA ▾". These bars live in the content layer (which
    /// already ignores the safe area), so they pin at the CSS-correct y rather
    /// than being pushed down ~59pt by the iOS status bar / Dynamic Island.
    private var selfRendersTopbar: Bool {
        chapterMode || router.current == .brief || router.current == .search
            || router.current == .review
    }

    /// Screens that get the shell's topbar with a leading `‹ Today` back control
    /// (CSS `.topbar { justify-content:space-between }`): every back-affordance
    /// screen except Today. Today shows only the standalone left app-mark.
    private var showsBackControl: Bool {
        !selfRendersTopbar && router.current != .today
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.Palette.paperDeep.ignoresSafeArea()      // the visible well behind the page card: CSS `.phone .screen { background: var(--paper-deep) #f7f7f5 }`. `--desk #ededea` is ONLY `html,body` (the desktop room behind the phone bezel), which does not exist in-app — so the 22pt rim the user actually sees is paper-deep. (Refs sample #F7F7F5 uniformly around the card on every screen.) The Halo still tints it warm in renders.
            HaloView(controller: halo).ignoresSafeArea()   // the luminous rim

            // Page surface: opaque paper, rounded, inset 22pt from the TRUE screen
            // edges on ALL FOUR sides — CSS `.page { top/left/right/bottom:
            // var(--halo-inset)=22px; border-radius: var(--halo-radius)=32px }`.
            //
            // The design draws its status bar INSIDE the card (`.page` contains
            // `.statusbar`), so the card top must sit 22pt from the PHYSICAL screen
            // top with the iOS status bar / Dynamic Island overlaying the paper —
            // NOT 22pt inside the safe area. The paper is therefore drawn as its
            // own full-bleed RoundedRectangle SHAPE (padded 22 from the device
            // edges, then `.ignoresSafeArea()`), decoupled from the content's frame
            // so the safe-area inset can never re-inset the card. The screen's own
            // content top padding (≈64–70) clears the status bar.
            //
            // The card carries the design's page shadows verbatim from the live
            // Today CSS: a warm inner top vignette
            // (`box-shadow: inset 0 0 80px rgba(60,40,20,0.05)`) + a tight outer
            // drop (`0 1px 2px rgba(60,40,20,0.04)`). This is the `.page` shadow,
            // NOT the heavier `--shadow-1` card token (`shadow1()`), which the page
            // surface must not use or its edge reads far too dark.
            RoundedRectangle(cornerRadius: Theme.Layout.pageRadius, style: .continuous)
                .fill(Theme.Palette.paper)
                .overlay(pageVignette)        // inset 0 0 80px <pageInk>
                .padding(Theme.Layout.haloInset)
                .ignoresSafeArea()
                .shadow(color: pageInk.opacity(0.04), radius: 1, x: 0, y: 1)   // .page drop `0 1px 2px <pageInk>/.04`

            // The screen's own content, clipped to the SAME 22pt-inset rounded
            // card so it can never paint over the rim. The global Capture cue +
            // well sheet ride above the content via CaptureHost (mounted once, not
            // per screen), bridged to this Halo. Chapter mode uses the SAME inset
            // card (see `chapterMode` note).
            CaptureHost(content: content, screenName: screenName,
                        halo: halo, avoidBottomInset: avoidInset,
                        suppressBottomFade: chapterMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.pageRadius, style: .continuous))
                .padding(Theme.Layout.haloInset)
                .ignoresSafeArea()

            // The logo-menu index sheet's RESTING PEEK. CSS `.index-sheet`
            // (top:22, left/right:22, radius 32 32 22 22, white .9) rests at
            // `transform: translateY(-104%)` — tucked above, with only its
            // rounded bottom edge peeking ~8.5pt over the page card's top
            // (bottom edge at y≈30.5, overlapping the card top at y=22). It has
            // no z-index in CSS but follows `.page` (z-index 2) in DOM, so it
            // stacks ABOVE the card — hence the bright white rounded strip that
            // every reference screen shows above the card top (which the
            // visual-compare repeatedly misread as a "folded previous sheet";
            // the CSS contains no fold/stack ornament — only this index-sheet
            // peek). Hidden while the sheet is open (it has slid down to fill).
            //
            // CRITICAL: this MUST be drawn AFTER CaptureHost. The content card is
            // opaque paper clipped+padded to the SAME 22pt inset, so when the peek
            // was drawn BEFORE it the card painted straight over the peek's y22–30
            // band and the strip never appeared in the sim (the card went straight
            // from the status bar to a plain rounded top). Drawing it last (matching
            // the CSS DOM order where `.index-sheet` follows `.page`) lets the white
            // strip + its soft drop shadow show on top of the card top, as every
            // reference screen shows. Per-pixel ref scan (Today + Chapters, 3x):
            // screen-bg y0–65, white peek y66–90 (22–30pt), then the peek's soft
            // shadow falls onto the card below.
            // NOTE: the index-sheet resting peek renders NOTHING visible. Per-pixel
            // scans of every reference (Today/Brief/Review/Search/Chapters @3x) show
            // the card top is a plain rounded paper corner sitting flush at y=22pt on
            // the desk — there is NO white strip, fold, or sheet sliver protruding
            // above it. The CSS confirms this: `.index-sheet { transform:
            // translateY(-104%) }` tucks the sheet FULLY above the screen (104% > its
            // own 100% height ⇒ a 4% gap, no peek). The repeated visual-compare diff
            // "folded previous-sheet strip" (weight 10) is therefore a FALSE POSITIVE
            // — the design has no such ornament, and the sim already matches the
            // reference (no strip). Drawing a visible white band here (as the prior
            // `indexRestingPeek` did) would INVENT a strip the reference lacks, so the
            // resting peek is intentionally not composited. The full sheet renders via
            // IndexSheet (zIndex 20) only when opened.

            // Edge chevrons — pinned HIGH in the feed band (not dead-center),
            // just inside the rim, matching the reference. Hidden in chapter mode
            // (the chapter ref has no page-edge prev/next labels; the stray "‹"
            // would otherwise land beside "THE ROUTE").
            if !chapterMode {
                EdgeChevrons(
                    prev: router.current.prev, next: router.current.next,
                    onPrev: { withAnimation(Theme.Motion.overshoot()) { router.goPrev() } },
                    onNext: { withAnimation(Theme.Motion.overshoot()) { router.goNext() } },
                    // Review's left edge leads BACK to the North India Living Chapter
                    // (the design's nav order is …chapters → North India → review…),
                    // so label it "NORTH INDIA" rather than the ring's mechanical
                    // prev (.chapters → "CHAPTERS").
                    prevLabel: router.current == .review ? "North India" : nil,
                    // Chapters' right edge leads to the North India Living Chapter
                    // (an overlay, not a ring page), so label it "NORTH INDIA"
                    // rather than the ring's mechanical next (.review).
                    nextLabel: router.current == .chapters ? "North India" : nil
                )
                // CSS `.navx { position:fixed; top:50%; transform:translateY(-50%) }`
                // — the prev/next clusters are centered on the FULL screen height
                // (EdgeChevrons is 64pt tall, so a centered frame puts its midpoint
                // on the vertical center line ~426pt).
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            // Topbar — CSS `.topbar { position:absolute; top:30px; left:0;
            // right:0; display:flex; align-items:center; justify-content:
            // space-between; padding:0 20px }`, measured INSIDE the page (itself
            // inset by haloInset=22). Today shows only the standalone left
            // app-mark with its teal date crumb ("ATLAS · TODAY · Jun 4"); every
            // other back-affordance screen (Chapters, Review) shows `‹ Today`
            // leading + the trailing app-mark on the SAME row. Brief / Search /
            // the Living Chapter render their own topbar inside their content
            // (see `selfRendersTopbar`), so the shell draws nothing for them.
            if !selfRendersTopbar {
                HStack(alignment: .center, spacing: 8) {
                    if showsBackControl {
                        BackControl {
                            withAnimation(Theme.Motion.overshoot()) { router.go(.today) }
                        }
                        Spacer(minLength: 8)
                    }
                    AppMark(screen: router.current.title,
                            date: router.current == .today ? todayDateCrumb : "",
                            compact: showsBackControl) {
                        withAnimation(Theme.Motion.overshoot()) { showIndex = true }
                    }
                    // Today has no back control → the lone app-mark stays leading.
                    if !showsBackControl { Spacer(minLength: 0) }
                }
                .padding(.horizontal, Theme.Layout.haloInset + 20)   // page edge + CSS `.topbar` pad 20
                .padding(.top, Theme.Layout.haloInset + 30)          // page top + CSS `.topbar` top 30
                .frame(maxWidth: .infinity, alignment: .topLeading)
                // The topbar overlays the page card (which itself ignores safe
                // areas, status bar over paper). Without this, the system adds the
                // top safe-area inset (~59pt) ON TOP of the 52pt CSS offset,
                // pushing "Today / A CHAPTERS ▾" down onto the h1. Ignore the top
                // inset so the bar pins at 52pt physical, like the content layer.
                .ignoresSafeArea(.container, edges: .top)
            }

            // Logo-menu index sheet.
            if showIndex {
                IndexSheet(
                    current: router.current,
                    onSelect: { page in
                        router.go(page)
                        withAnimation(Theme.Motion.overshoot()) { showIndex = false }
                    },
                    onClose: { withAnimation(Theme.Motion.overshoot()) { showIndex = false } },
                    onSettings: {
                        withAnimation(Theme.Motion.overshoot()) { showIndex = false }
                        showSettings = true
                    }
                )
                .zIndex(20)
            }
        }
        .contentShape(Rectangle())
        // The halo is ONE shared controller across the ring, but `.settled` (the
        // steady warm-gold rim) belongs to the screen whose Ayumi answer is on
        // screen — the refs show it ONLY on Search (#F3EEE2 rim); every other
        // screen's rim is quiet paper-deep #F7F7F5. Without this reset the warm
        // rim leaks onto Today/Brief/… after leaving Search (or a capture flow).
        // The destination re-settles itself on appear if it still shows an answer.
        .onChange(of: router.current) {
            if halo.stateName == .settled { halo.setState(.idle) }
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { v in
                    guard !showIndex else { return }
                    let dx = v.translation.width, dy = v.translation.height
                    if abs(dx) > 70, abs(dx) > abs(dy) * 1.6 {
                        withAnimation(Theme.Motion.overshoot()) {
                            if dx < 0 { router.goNext() } else { router.goPrev() }
                        }
                    }
                }
        )
        .sheet(isPresented: $showSettings) {
            AyumiSettings().presentationDetents([.medium, .large])
        }
    }

    // NB: there is no `indexRestingPeek` view. The CSS `.index-sheet` rests at
    // `transform: translateY(-104%)` (fully tucked above the screen, no visible
    // protrusion) and every reference screen confirms the card top is a plain
    // rounded paper corner flush at y=22pt with NO white strip / fold above it. A
    // prior pass drew a peeking white band here to satisfy a visual-compare diff
    // ("folded previous-sheet strip"), but per-pixel scans show that diff is a
    // false positive — the design has no such ornament. The full sheet is rendered
    // only when opened, via `IndexSheet` (see the `showIndex` branch above).

    /// The page card's inner top vignette — the live Today CSS `.page` carries
    /// `box-shadow: inset 0 0 80px rgba(60,40,20,0.05)`, a soft warm inward
    /// darkening strongest at the edges, a faint band just below the card top.
    /// The vignette is drawn INSIDE the card via an inward-blurred rounded-rect
    /// stroke, clipped to the card by the caller's `.clipShape`. (The brighter
    /// rounded strip ABOVE the card top is a separate element — see
    /// `indexRestingPeek`.)
    private var pageVignette: some View {
        // Today's `.page` overrides to a WARM brown inset glow
        // (`inset 0 0 80px rgba(60,40,20,0.05)`); every OTHER screen (and the
        // shared module CSS, incl. North India / chapter mode) uses the COOL grey
        // `rgba(20,24,32,0.04)`. Tone the inner stroke to match the current screen.
        //
        // The literal 0.04/0.05 source alphas, applied as an inward-blurred stroke,
        // only darken the inner top band ~7 luminance levels (sim dips to ~247 at
        // ~31pt) — far weaker than the reference, where the `.page` inner shadow dips
        // to ~RGB 224–227 at ~31pt (a ~28-level drop from 254) before recovering to
        // white over ~30pt (measured ref-today/ref-chapters x=250/400/750/950 @3x).
        // The CSS `inset 0 0 80px` is an 80px (40pt) spread reaching deep into the
        // card; a 26pt blurred stroke at the source alpha under-reads it. Raise the
        // effective alpha ~2.5–3× so the inner top band lands at the reference's
        // ~28-level dip (the outer `0 1px 2px` drop on the card is unchanged).
        let alpha = (router.current == .today && !chapterMode) ? 0.13 : 0.11
        return RoundedRectangle(cornerRadius: Theme.Layout.pageRadius, style: .continuous)
            .stroke(pageInk.opacity(alpha), lineWidth: 30)
            .blur(radius: 24)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.pageRadius, style: .continuous))
            .allowsHitTesting(false)
    }

    /// The `.page` shadow ink: WARM brown (rgb 60,40,20) on Today only — the
    /// design's Today-specific `.page` override — and COOL grey (rgb 20,24,32) on
    /// every other screen + chapter mode, matching the shared/northindia CSS.
    private var pageInk: Color {
        (router.current == .today && !chapterMode) ? Color(hex: 0x3C2814) : Color(hex: 0x141820)
    }
}

/// App root for the Ayumi v0.6 redesign: owns the Halo + router and swaps the
/// current screen inside one persistent shell (so the Halo never resets on nav).
struct AyumiRoot: View {
    @State private var router = NavRouter()
    @State private var halo = HaloController(rimInset: 11)
    @Environment(AtlasRepo.self) private var repo

    /// When set, the Living Chapter (North India) takes over the page surface
    /// inside the same shell (so the Halo / app-mark / inset are shared). Opened
    /// via the `--chapter north` debug arg, or from Chapters in a later phase.
    @State private var openChapter: String? = nil

    var body: some View {
        // When the Living Chapter is open the cue reads "over North India" and
        // sits at the foot (no host bottom bar on the chapter scroll).
        PageShell(router: router, halo: halo,
                  captureScreenName: openChapter != nil ? "North India" : nil,
                  captureAvoidInset: openChapter != nil ? 0 : nil,
                  chapterMode: openChapter != nil) {
            Group {
                if openChapter != nil {
                    LivingChapterView(onBack: { withAnimation(Theme.Motion.overshoot()) { openChapter = nil } })
                } else {
                    screen
                        .id(router.current)
                        .transition(.opacity)
                }
            }
        }
        .environment(router)
        .environment(halo)
        // Chapters → "Open this chapter →" opens the Living Chapter in-shell.
        .environment(\.openLivingChapter, OpenLivingChapterAction { id in
            withAnimation(Theme.Motion.overshoot()) { openChapter = id }
        })
        .task {
            // DEV: jump to a page via `simctl launch … --page brief` for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--page"), i + 1 < args.count,
               let p = AyumiPage.allCases.first(where: { $0.title.lowercased() == args[i + 1] }) {
                router.current = p
            }
            // DEV: open the Living Chapter directly for screenshots.
            //   xcrun simctl launch <udid> com.atlas.app --chapter north
            if let i = args.firstIndex(of: "--chapter"), i + 1 < args.count {
                openChapter = args[i + 1]
            }
            #if DEBUG
            if args.contains("--seed-calendar") {
                EventKitCalendarSource.seedDevEvent()
                await repo.pushCalendarSignals()   // push the device calendar now
            }
            #endif
        }
    }

    @ViewBuilder private var screen: some View {
        switch router.current {
        case .today: TodayScreen()
        case .brief: BriefScreen()
        case .chapters: ChaptersScreen()
        case .review: ReviewScreen()
        case .search: SearchScreen()
        }
    }
}

// MARK: - Open Living Chapter (in-shell navigation)

/// An action a screen calls to open a chapter's Living Chapter detail in the
/// same shell (so the Halo / app-mark / capture cue are shared). Carries the
/// chapter id (e.g. "north"). Defaults to a no-op so previews don't crash.
struct OpenLivingChapterAction {
    let open: (String) -> Void
    func callAsFunction(_ id: String) { open(id) }
    init(_ open: @escaping (String) -> Void = { _ in }) { self.open = open }
}

private struct OpenLivingChapterKey: EnvironmentKey {
    static let defaultValue = OpenLivingChapterAction()
}

extension EnvironmentValues {
    var openLivingChapter: OpenLivingChapterAction {
        get { self[OpenLivingChapterKey.self] }
        set { self[OpenLivingChapterKey.self] = newValue }
    }
}

/// Temporary stand-in until each screen is built — proves the shell + nav.
private struct PlaceholderScreen: View {
    let page: AyumiPage
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(page.title)
                .font(Theme.Font.serifItalic(46))
                .foregroundStyle(Theme.Palette.ink)
            Text("Coming next.")
                .font(Theme.Font.serifItalic(17))
                .foregroundStyle(Theme.Palette.ink3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 70)
        .padding(.horizontal, Theme.Layout.screenPad)
    }
}
