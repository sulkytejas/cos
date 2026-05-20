import SwiftUI
import SwiftData

@main
struct AtlasApp: App {
    let container: ModelContainer

    init() {
        self.container = AppContainer.make()
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .tint(Theme.Palette.moss)
        }
        .modelContainer(container)
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
