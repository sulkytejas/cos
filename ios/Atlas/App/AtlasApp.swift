import SwiftUI
import SwiftData
import os

@main
struct AtlasApp: App {
    let container: ModelContainer
    /// The single SwiftData writer (SERVER_ARCHITECTURE.md §4.e). The brain runs
    /// on the server; this thin client only swaps imperative calls onto the repo
    /// and mirrors server rows into the cache for the `@Query` reads.
    @State private var repo: AtlasRepo
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = AppContainer.make()
        self.container = container
        // Build the repo on the container's main context (it is `@MainActor`).
        _repo = State(initialValue: AtlasRepo(context: ModelContext(container)))
        configureAppearance()
        dumpFontRegistry()
        // Dev-only band override via launch arg. Run with:
        //   xcrun simctl launch <udid> com.atlas.app --AYUMI_BAND afternoon
        if let i = CommandLine.arguments.firstIndex(of: "--AYUMI_BAND"),
           i + 1 < CommandLine.arguments.count {
            switch CommandLine.arguments[i + 1].lowercased() {
            case "morning":   TimeBand.debugOverride = .morning
            case "afternoon": TimeBand.debugOverride = .afternoon
            case "evening":   TimeBand.debugOverride = .evening
            case "night":     TimeBand.debugOverride = .night
            default: break
            }
        }
        // Ask for calendar access so EventKit can be pushed to the server as
        // `calendar` signals (the device-only push source, §4.e).
        //
        // SKIP this eager request during screenshot / dev launches: when any
        // pixel-match capture arg is present (`--page`, `--chapter`, `--query`,
        // `--seed-calendar`, `--capture`) the OS would otherwise present the
        // full-access calendar permission alert ("'Ayumi' Would Like Full Access
        // to Your Calendar") immediately on launch, centered over whatever screen
        // is being captured, with a dimming scrim that occludes/desaturates the
        // frame. The permission isn't part of any screen's UI — gate it so the
        // alert never renders during capture. (For real runs the request still
        // fires; for a granted capture, pre-authorize the sim:
        // `xcrun simctl privacy <udid> grant calendar com.atlas.app`.)
        let captureArgs: Set<String> = ["--page", "--chapter", "--query", "--seed-calendar", "--capture"]
        if !CommandLine.arguments.contains(where: captureArgs.contains) {
            Task { await EventKitCalendarSource.requestAccess() }
        }
    }

    /// One-time print of every bundled font family + PostScript names so we
    /// can confirm `Font.custom(...)` references resolve. Filter to our families.
    private func dumpFontRegistry() {
        let log = Logger(subsystem: "com.atlas.app", category: "Fonts")
        let interesting = ["Instrument", "Manrope", "JetBrains"]
        for family in UIFont.familyNames.sorted() where interesting.contains(where: family.contains) {
            let names = UIFont.fontNames(forFamilyName: family)
            log.info("\(family, privacy: .public) → \(names.joined(separator: ", "), privacy: .public)")
        }
    }

    @State private var splashDone: Bool = false

    /// While `true`, the app launches into the Ayumi v0.6 redesign (the new
    /// shell + screens). Flip to `false` to restore the legacy v0.3 UI.
    private static let showAyumi = true

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--capture") {
                // DEBUG-only: verify the Capture system (cue + well) in isolation.
                CapturePreviewScreen()
                    .environment(repo)
                    .preferredColorScheme(.light)
            } else if Self.showAyumi {
                AyumiRoot()
                    .environment(repo)
                    .preferredColorScheme(.light)
            } else {
                legacyRoot
            }
            #else
            if Self.showAyumi {
                AyumiRoot()
                    .environment(repo)
                    .preferredColorScheme(.light)
            } else {
                legacyRoot
            }
            #endif
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // The brain is server-side (§4.e). On foreground: pull server rows
            // into the cache mirror, then push the device calendar as signals
            // (idempotent — the server upserts on `(source, externalId)`).
            // `.local` is the developer-only offline fallback — no server I/O.
            guard DataSource.current.isServer else { return }
            if phase == .active {
                Task {
                    await repo.sync()
                    await repo.pushCalendarSignals()
                }
            }
        }
    }

    /// The legacy v0.3 root (splash → RootView), extracted so both the DEBUG and
    /// release `WindowGroup` branches can reuse it.
    @ViewBuilder private var legacyRoot: some View {
        ZStack {
            RootView()
                .preferredColorScheme(.light)
                .tint(Theme.Palette.moss)
                .opacity(splashDone ? 1 : 0)

            if !splashDone {
                SplashView(onComplete: { splashDone = true })
                    .transition(.opacity)
            }
        }
    }

    private func configureAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "ColorPaper")
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(named: "ColorInk") ?? .black
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(named: "ColorInk") ?? .black
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(named: "ColorPaper")
        tabAppearance.shadowColor = UIColor(named: "ColorBorderWarm")
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
