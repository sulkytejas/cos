import Foundation
import SwiftData

enum AppContainer {
    static let schema = Schema([
        // v0.1
        Chapter.self,
        Todo.self,
        Decision.self,
        Entry.self,
        ChapterLink.self,
        // v0.2 — agentic surface
        Brief.self,
        Watcher.self,
        Proposal.self,
        Signal.self,
        AppEvent.self,
    ])

    static func make() -> ModelContainer {
        let config = ModelConfiguration(
            "atlas",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            seedIfEmpty(context: ModelContext(container))
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    static func seedIfEmpty(context: ModelContext) {
        let descriptor = FetchDescriptor<Chapter>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        if existing == 0 {
            Seed.run(in: context)
        }
        // v0.2 — briefs / proposals / watchers, idempotent inside.
        Task { @MainActor in SeedV2.run(in: context) }
    }
}
