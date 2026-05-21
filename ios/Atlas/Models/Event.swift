import Foundation
import SwiftData

/// An Event — the queue the agent consumes. Web/iOS write here, the agent
/// service (Phase 2) drains it.
@Model
final class AppEvent {
    @Attribute(.unique) var id: UUID
    var typeRaw: String                // chapter_created / capture_received / …
    var payloadJSON: Data
    var statusRaw: String              // pending / processing / done / failed
    var createdAt: Date
    var processedAt: Date?
    var error: String?

    init(
        id: UUID = UUID(),
        type: EventType,
        payload: Encodable
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.payloadJSON = (try? JSONEncoder().encode(AnyEncodable(payload))) ?? Data()
        self.statusRaw = EventStatus.pending.rawValue
        self.createdAt = Date()
    }

    var type: EventType {
        get { EventType(rawValue: typeRaw) ?? .captureReceived }
        set { typeRaw = newValue.rawValue }
    }
    var status: EventStatus {
        get { EventStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

enum EventType: String, Codable, CaseIterable {
    case chapterCreated = "chapter_created"
    case chapterUpdated = "chapter_updated"
    case captureReceived = "capture_received"
    case signalReceived = "signal_received"
    case timeTrigger = "time_trigger"
    case watcherDue = "watcher_due"
    case briefActedOn = "brief_acted_on"
    case dailyScan = "daily_scan"
}

enum EventStatus: String, Codable, CaseIterable {
    case pending, processing, done, failed
}

private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
