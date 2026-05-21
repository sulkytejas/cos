import Foundation
import SwiftData

/// A Watcher — a standing instruction Atlas leaves for itself.
@Model
final class Watcher {
    @Attribute(.unique) var id: UUID
    var watcherDescription: String     // "VFS appointment slots before Jun 28"
    var prompt: String                 // what to look for on recheck
    var sourceTypeRaw: String          // web / gmail / calendar / drive / internal
    var lastChecked: Date?
    var nextCheck: Date
    var cadenceMinutes: Int
    var statusRaw: String              // active / paused / completed
    var lastFindingJSON: Data?
    /// Short display label e.g. "every 3h", "on inbox", "daily".
    var cadenceLabel: String?
    var createdAt: Date

    var chapter: Chapter?

    init(
        id: UUID = UUID(),
        watcherDescription: String,
        prompt: String,
        sourceType: WatcherSourceType = .internalSource,
        nextCheck: Date = Date().addingTimeInterval(60 * 60),
        cadenceMinutes: Int = 180,
        cadenceLabel: String? = nil,
        chapter: Chapter? = nil
    ) {
        self.id = id
        self.watcherDescription = watcherDescription
        self.prompt = prompt
        self.sourceTypeRaw = sourceType.rawValue
        self.nextCheck = nextCheck
        self.cadenceMinutes = cadenceMinutes
        self.cadenceLabel = cadenceLabel
        self.statusRaw = WatcherStatus.active.rawValue
        self.createdAt = Date()
        self.chapter = chapter
    }

    var sourceType: WatcherSourceType {
        get { WatcherSourceType(rawValue: sourceTypeRaw) ?? .internalSource }
        set { sourceTypeRaw = newValue.rawValue }
    }
    var status: WatcherStatus {
        get { WatcherStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}

enum WatcherSourceType: String, Codable, CaseIterable {
    case web, gmail, calendar, drive
    case internalSource = "internal"
}

enum WatcherStatus: String, Codable, CaseIterable {
    case active, paused, completed
}
