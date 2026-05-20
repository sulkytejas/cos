import Foundation
import SwiftData

@Model
final class Chapter {
    @Attribute(.unique) var id: UUID
    var title: String
    var typeRaw: String
    var statusRaw: String
    var startDate: Date?
    var endDate: Date?
    var purpose: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Todo.chapter)
    var todos: [Todo] = []

    @Relationship(deleteRule: .cascade, inverse: \Decision.chapter)
    var decisions: [Decision] = []

    @Relationship(deleteRule: .cascade, inverse: \Entry.chapter)
    var entries: [Entry] = []

    @Relationship(deleteRule: .cascade, inverse: \ChapterLink.fromChapter)
    var outgoingLinks: [ChapterLink] = []

    @Relationship(deleteRule: .cascade, inverse: \ChapterLink.toChapter)
    var incomingLinks: [ChapterLink] = []

    init(
        id: UUID = UUID(),
        title: String,
        type: ChapterType,
        status: ChapterStatus = .active,
        startDate: Date? = nil,
        endDate: Date? = nil,
        purpose: String? = nil
    ) {
        self.id = id
        self.title = title
        self.typeRaw = type.rawValue
        self.statusRaw = status.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.purpose = purpose
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var type: ChapterType {
        get { ChapterType(rawValue: typeRaw) ?? .personal }
        set { typeRaw = newValue.rawValue }
    }

    var status: ChapterStatus {
        get { ChapterStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var openTodos: [Todo] { todos.filter { !$0.done } }
    var doneTodos: [Todo] { todos.filter { $0.done } }

    var progress: Double {
        guard !todos.isEmpty else { return 0 }
        return Double(doneTodos.count) / Double(todos.count)
    }

    func touch() { updatedAt = Date() }
}
