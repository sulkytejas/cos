import Foundation
import SwiftData

/// A Brief — Atlas's prepared preparation document for a recognised situation.
/// `structureData` is JSON-encoded BriefStructure (see Lib/BriefStructure.swift).
@Model
final class Brief {
    @Attribute(.unique) var id: UUID
    var title: String
    var situationDescription: String

    /// JSON-encoded array of `{ kind, data }` sections — see BriefStructure.swift.
    /// Stored as Data (not String) so SwiftData treats it as a blob with no
    /// collation worry. Decode lazily at render time.
    var structureData: Data

    var statusRaw: String
    var surfaceAt: Date
    var expiresAt: Date?

    var chapterTitle: String?
    var relevance: String?
    var when: String?
    var drafted: String?
    var preview: String?

    var primaryAction: String?
    var secondaryActionsJSON: Data?

    /// JSON-encoded trace for debugging.
    var agentTraceJSON: Data?
    var createdAt: Date

    var chapter: Chapter?

    init(
        id: UUID = UUID(),
        title: String,
        situationDescription: String,
        structureData: Data,
        status: BriefStatus = .surfaced,
        surfaceAt: Date = Date(),
        expiresAt: Date? = nil,
        chapter: Chapter? = nil,
        chapterTitle: String? = nil,
        relevance: String? = nil,
        when: String? = nil,
        drafted: String? = nil,
        preview: String? = nil,
        primaryAction: String? = nil,
        secondaryActions: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.situationDescription = situationDescription
        self.structureData = structureData
        self.statusRaw = status.rawValue
        self.surfaceAt = surfaceAt
        self.expiresAt = expiresAt
        self.chapter = chapter
        self.chapterTitle = chapterTitle
        self.relevance = relevance
        self.when = when
        self.drafted = drafted
        self.preview = preview
        self.primaryAction = primaryAction
        if let secondaryActions {
            self.secondaryActionsJSON = try? JSONEncoder().encode(secondaryActions)
        }
        self.createdAt = Date()
    }

    var status: BriefStatus {
        get { BriefStatus(rawValue: statusRaw) ?? .surfaced }
        set { statusRaw = newValue.rawValue }
    }

    var secondaryActions: [String] {
        guard let data = secondaryActionsJSON else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

enum BriefStatus: String, Codable, CaseIterable {
    case draft, surfaced, dismissed, actedOn = "acted_on", archived, failed
}
