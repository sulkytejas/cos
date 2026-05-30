import SwiftUI
import SwiftData
import os

@main
struct AtlasApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        self.container = AppContainer.make()
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
        // Hand the container to the agent + register the BG refresh task.
        // Must happen before the app finishes launching (Apple docs).
        let captured = self.container
        Task { await AtlasAgent.shared.attach(container: captured) }
        BackgroundRefresh.register()
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
            if Self.showAyumi {
                AyumiRoot()
                    .preferredColorScheme(.light)
            } else {
                ZStack {
                    RootView()
                        .preferredColorScheme(.light)
                        .tint(Theme.Palette.moss)
                        .opacity(splashDone ? 1 : 0)

                    if !splashDone {
                        SplashView(onComplete: {
                            splashDone = true
                        })
                        .transition(.opacity)
                    }
                }
            }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await AtlasAgent.shared.startForegroundLoop() }
            case .background:
                Task { await AtlasAgent.shared.stopForegroundLoop() }
                BackgroundRefresh.schedule()
            default:
                break
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
