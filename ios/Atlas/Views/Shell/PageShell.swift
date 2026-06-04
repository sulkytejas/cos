import SwiftUI

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
    @ViewBuilder var content: () -> Content

    @State private var showIndex = false
    @State private var showSettings = false

    private var screenName: String { captureScreenName ?? router.current.title }
    private var avoidInset: CGFloat { captureAvoidInset ?? router.current.captureAvoidInset }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.Palette.paperDeep.ignoresSafeArea()      // shows in the rim corners
            HaloView(controller: halo).ignoresSafeArea()   // the luminous rim

            // Page surface: opaque paper, rounded, inset 22 within the safe area.
            // The global Capture cue + well sheet ride above the page content via
            // CaptureHost (mounted once, not per screen), bridged to this Halo.
            CaptureHost(content: content, screenName: screenName,
                        halo: halo, avoidBottomInset: avoidInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.Palette.paper)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.pageRadius, style: .continuous))
                .padding(Theme.Layout.haloInset)
                .shadow1()

            // Edge chevrons — vertically centered, just inside the rim.
            EdgeChevrons(
                prev: router.current.prev, next: router.current.next,
                onPrev: { withAnimation(Theme.Motion.overshoot()) { router.goPrev() } },
                onNext: { withAnimation(Theme.Motion.overshoot()) { router.goNext() } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // App-mark — top-left of the page.
            AppMark(screen: router.current.title) {
                withAnimation(Theme.Motion.overshoot()) { showIndex = true }
            }
            .padding(.top, 30)
            .padding(.leading, Theme.Layout.haloInset + Theme.Layout.screenPad)

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
                  captureAvoidInset: openChapter != nil ? 0 : nil) {
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
