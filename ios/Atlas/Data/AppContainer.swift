import Foundation
import SwiftData

enum AppContainer {
    static let schema = Schema([
        Chapter.self,
        Todo.self,
        Decision.self,
        Entry.self,
        ChapterLink.self
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
        guard existing == 0 else { return }
        Seed.run(in: context)
    }
}
