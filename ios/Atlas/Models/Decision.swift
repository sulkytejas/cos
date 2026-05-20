import Foundation
import SwiftData

@Model
final class Decision {
    @Attribute(.unique) var id: UUID
    var title: String
    var rationale: String?
    var optionsConsidered: String?
    var decidedAt: Date
    var createdAt: Date

    var chapter: Chapter?

    init(
        id: UUID = UUID(),
        title: String,
        rationale: String? = nil,
        optionsConsidered: String? = nil,
        decidedAt: Date = Date(),
        chapter: Chapter? = nil
    ) {
        self.id = id
        self.title = title
        self.rationale = rationale
        self.optionsConsidered = optionsConsidered
        self.decidedAt = decidedAt
        self.createdAt = Date()
        self.chapter = chapter
    }
}
