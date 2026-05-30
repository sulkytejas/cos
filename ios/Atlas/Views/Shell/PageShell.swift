import SwiftUI

/// The shared shell every Ayumi screen sits in: a full-bleed Halo behind an
/// opaque paper page surface inset 22pt (radius 32), with the app-mark, edge
/// chevrons, the logo-menu index sheet, and horizontal-swipe navigation.
/// The screen's own content is supplied via `content` and owns its internal
/// padding (top ~70 to clear the app-mark).
struct PageShell<Content: View>: View {
    var router: NavRouter
    var halo: HaloController
    @ViewBuilder var content: () -> Content

    @State private var showIndex = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.Palette.paperDeep.ignoresSafeArea()      // shows in the rim corners
            HaloView(controller: halo).ignoresSafeArea()   // the luminous rim

            // Page surface: opaque paper, rounded, inset 22 within the safe area.
            content()
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
                    onClose: { withAnimation(Theme.Motion.overshoot()) { showIndex = false } }
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
    }
}

/// App root for the Ayumi v0.6 redesign: owns the Halo + router and swaps the
/// current screen inside one persistent shell (so the Halo never resets on nav).
struct AyumiRoot: View {
    @State private var router = NavRouter()
    @State private var halo = HaloController(rimInset: 11)

    var body: some View {
        PageShell(router: router, halo: halo) {
            screen
                .id(router.current)
                .transition(.opacity)
        }
        .environment(router)
        .environment(halo)
        .task {
            // DEV: jump to a page via `simctl launch … --page brief` for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--page"), i + 1 < args.count,
               let p = AyumiPage.allCases.first(where: { $0.title.lowercased() == args[i + 1] }) {
                router.current = p
            }
        }
    }

    @ViewBuilder private var screen: some View {
        switch router.current {
        case .today: TodayScreen()
        case .brief: BriefScreen()
        case .capture: CaptureScreen()
        case .chapters: ChaptersScreen()
        case .review: ReviewScreen()
        case .search: SearchScreen()
        }
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
