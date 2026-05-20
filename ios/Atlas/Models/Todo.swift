import Foundation
import SwiftData

@Model
final class Todo {
    @Attribute(.unique) var id: UUID
    var text: String
    var done: Bool
    var dueDate: Date?
    var sourceRaw: String
    var createdAt: Date
    var doneAt: Date?

    var chapter: Chapter?

    init(
        id: UUID = UUID(),
        text: String,
        done: Bool = false,
        dueDate: Date? = nil,
        source: TodoSource = .manual,
        chapter: Chapter? = nil
    ) {
        self.id = id
        self.text = text
        self.done = done
        self.dueDate = dueDate
        self.sourceRaw = source.rawValue
        self.createdAt = Date()
        self.doneAt = nil
        self.chapter = chapter
    }

    var source: TodoSource {
        get { TodoSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
