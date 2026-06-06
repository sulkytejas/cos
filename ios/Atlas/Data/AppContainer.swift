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
        // Today agentic flow v1 — the conversational thread (mirrors `turns`).
        Turn.self,
        // v0.6 Phase 4 — delta-sync bookkeeping (SERVER_ARCHITECTURE.md §4.d/§4.e):
        // durable per-table cursor, write-through outbox queue, one-way
        // bootstrap latch. Kept in the SAME store as the mirror.
        SyncCursor.self,
        OutboxItem.self,
        SyncMigration.self,
    ])

    static func make() -> ModelContainer {
        // The store name is chosen by the DataSource flag: `.server` uses the
        // "atlas" cache mirror; the developer-only `.local` fallback uses a
        // SEPARATE "atlas-local" store so the two engines never alias one store
        // (the split-brain guard, SERVER_ARCHITECTURE.md §4.d).
        let config = ModelConfiguration(
            DataSource.current.storeName,
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
