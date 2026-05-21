import Foundation
import SwiftData

/// A Signal — raw external data Atlas has ingested. Connectors write here.
@Model
final class Signal {
    @Attribute(.unique) var id: UUID
    var sourceRaw: String              // gmail / calendar / drive / manual / voice
    var externalId: String?
    var rawDataJSON: Data
    var summary: String?
    var processed: Bool
    var arrivedAt: Date

    init(
        id: UUID = UUID(),
        source: SignalSource,
        externalId: String? = nil,
        rawData: Encodable,
        summary: String? = nil,
        arrivedAt: Date = Date()
    ) {
        self.id = id
        self.sourceRaw = source.rawValue
        self.externalId = externalId
        self.rawDataJSON = (try? JSONEncoder().encode(AnyEncodable(rawData))) ?? Data()
        self.summary = summary
        self.processed = false
        self.arrivedAt = arrivedAt
    }

    var source: SignalSource {
        get { SignalSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

enum SignalSource: String, Codable, CaseIterable {
    case gmail, calendar, drive, manual, voice
}

private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
