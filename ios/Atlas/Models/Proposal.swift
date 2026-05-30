import Foundation
import SwiftData

/// A Proposal — something Atlas would like to file but isn't sure about, OR
/// has already filed (status=approved) so the Review surface can show the
/// "Atlas filed:" history.
@Model
final class Proposal {
    @Attribute(.unique) var id: UUID
    var typeRaw: String                // todo / decision / journal_entry / chapter / chapter_link

    /// JSON of the would-be payload.
    var proposedPayloadJSON: Data

    var sourceBriefId: UUID?
    /// JSON-encoded array of source signal UUIDs.
    var sourceSignalIdsJSON: Data?

    var statusRaw: String              // pending / approved / edited / dismissed
    var confidence: Double             // 0..1
    var reasoning: String?
    /// One-line summary used in Review's "Atlas filed:" log.
    var summary: String?
    var sourceLabel: String?           // "Email" / "Calendar" / "Voice memo" / etc.
    var sourceMeta: String?            // "from karan@... · 06:12"

    /// "asked" proposals carry these — question shape with two tappable options.
    var question: String?
    var setup: String?
    /// JSON-encoded array of { label, value, result, type }
    var optionsJSON: Data?

    var createdAt: Date
    var decidedAt: Date?
    var decidedPayloadJSON: Data?

    var chapter: Chapter?

    init(
        id: UUID = UUID(),
        type: ProposalType,
        proposedPayload: Encodable,
        confidence: Double,
        chapter: Chapter? = nil,
        status: ProposalStatus = .pending,
        summary: String? = nil,
        sourceLabel: String? = nil,
        sourceMeta: String? = nil,
        question: String? = nil,
        setup: String? = nil,
        options: [ProposalOption]? = nil,
        reasoning: String? = nil,
        sourceBriefId: UUID? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.proposedPayloadJSON = (try? JSONEncoder().encode(AnyEncodable(proposedPayload))) ?? Data()
        self.confidence = confidence
        self.chapter = chapter
        self.statusRaw = status.rawValue
        self.summary = summary
        self.sourceLabel = sourceLabel
        self.sourceMeta = sourceMeta
        self.question = question
        self.setup = setup
        if let options {
            self.optionsJSON = try? JSONEncoder().encode(options)
        }
        self.reasoning = reasoning
        self.sourceBriefId = sourceBriefId
        self.createdAt = Date()
    }

    var type: ProposalType {
        get { ProposalType(rawValue: typeRaw) ?? .todo }
        set { typeRaw = newValue.rawValue }
    }
    var status: ProposalStatus {
        get { ProposalStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
    var options: [ProposalOption] {
        guard let data = optionsJSON else { return [] }
        return (try? JSONDecoder().decode([ProposalOption].self, from: data)) ?? []
    }
}

enum ProposalType: String, Codable, CaseIterable {
    case todo
    case decision
    case journalEntry = "journal_entry"
    case chapter
    case chapterLink = "chapter_link"
}

enum ProposalStatus: String, Codable, CaseIterable {
    case pending, approved, edited, dismissed
}

struct ProposalOption: Codable, Hashable {
    let label: String
    let value: String
    let result: String?
    let type: String?
}

/// Tiny eraser so we can store arbitrary Encodable payloads as JSON.
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

// MARK: - Materialisation

extension Proposal {
    /// Turn this proposal into the real record it proposes (todo / decision /
    /// journal entry / chapter) and mark it approved. Single source of truth,
    /// shared by the Review queue and the "Ayumi noticed" card so the
    /// materialisation logic isn't duplicated.
    func materialize(in context: ModelContext) {
        let payload = (try? JSONSerialization.jsonObject(with: proposedPayloadJSON)) as? [String: Any]
        switch type {
        case .todo:
            if let text = payload?["text"] as? String {
                let t = Todo(text: text, chapter: chapter)
                t.source = .extracted
                if let due = payload?["due"] as? String,
                   let date = ISO8601DateFormatter().date(from: due) {
                    t.dueDate = date
                }
                context.insert(t)
            }
        case .decision:
            if let title = payload?["title"] as? String {
                let rationale = (payload?["rationale"] as? String) ?? ""
                context.insert(Decision(title: title, rationale: rationale, decidedAt: Date(), chapter: chapter))
            }
        case .journalEntry:
            if let content = payload?["content"] as? String {
                context.insert(Entry(date: Date(), content: content, source: .manual, chapter: chapter))
            }
        case .chapter:
            if let title = payload?["title"] as? String,
               let typeStr = payload?["type"] as? String,
               let ctype = ChapterType(rawValue: typeStr) {
                context.insert(Chapter(title: title, type: ctype, purpose: payload?["purpose"] as? String))
            }
        case .chapterLink:
            break  // needs both chapter UUIDs — handled elsewhere
        }
        status = .approved
        decidedAt = Date()
        chapter?.touch()
    }
}
