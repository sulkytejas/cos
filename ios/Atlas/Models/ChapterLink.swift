import Foundation
import SwiftData

@Model
final class ChapterLink {
    @Attribute(.unique) var id: UUID
    var relationRaw: String
    var note: String?
    var createdAt: Date

    var fromChapter: Chapter?
    var toChapter: Chapter?

    init(
        id: UUID = UUID(),
        from: Chapter,
        to: Chapter,
        relation: LinkRelation,
        note: String? = nil
    ) {
        self.id = id
        self.relationRaw = relation.rawValue
        self.note = note
        self.createdAt = Date()
        self.fromChapter = from
        self.toChapter = to
    }

    var relation: LinkRelation {
        get { LinkRelation(rawValue: relationRaw) ?? .related }
        set { relationRaw = newValue.rawValue }
    }
}
