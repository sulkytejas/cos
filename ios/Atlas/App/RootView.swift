import SwiftUI

struct RootView: View {
    @State private var selection: Tab = .today
    @State private var showCapture = false

    enum Tab: Hashable {
        case today, chapters, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                TodayView(openCapture: { showCapture = true })
            }
            .tabItem {
                Label("Today", systemImage: "sun.max")
            }
            .tag(Tab.today)

            NavigationStack {
                ChaptersListView()
            }
            .tabItem {
                Label("Chapters", systemImage: "books.vertical")
            }
            .tag(Tab.chapters)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(Tab.settings)
        }
        .background(Theme.Palette.paper)
        .sheet(isPresented: $showCapture) {
            CaptureSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .bottomTrailing) {
            CaptureFAB(action: { showCapture = true })
                .padding(.trailing, 20)
                .padding(.bottom, 70)
        }
    }
}

struct CaptureFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Palette.paper)
                .frame(width: 56, height: 56)
                .background(Theme.Palette.moss)
                .clipShape(Circle())
                .shadow(color: Theme.Palette.moss.opacity(0.45), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick capture")
    }
}
