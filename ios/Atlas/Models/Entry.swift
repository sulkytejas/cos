import Foundation
import SwiftData

@Model
final class Entry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var content: String
    var sourceRaw: String
    var createdAt: Date

    var chapter: Chapter?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        content: String,
        source: EntrySource = .manual,
        chapter: Chapter? = nil
    ) {
        self.id = id
        self.date = date
        self.content = content
        self.sourceRaw = source.rawValue
        self.createdAt = Date()
        self.chapter = chapter
    }

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
