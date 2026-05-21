import Foundation

/// Brief structure — the Codable contract the BriefRenderer consumes.
/// Mirrors `src/lib/brief-schema.ts` on the web side, kind for kind.
///
/// Add a new component by: extend `BriefSectionKind`, define a matching
/// `XxxData` struct, add the case to `BriefSection.data`, register a
/// SwiftUI component, add to `BriefRenderer`.

public struct BriefStructure: Codable {
    public let sections: [BriefSection]

    public init(sections: [BriefSection]) {
        self.sections = sections
    }
}

public enum BriefSectionKind: String, Codable {
    case person, timeline, prediction, materials, options, tactical, quote, watcher, diff, action
}

/// Discriminated union over the 10 section kinds. Encodes/decodes JSON of
/// the shape `{ "kind": "person", "data": { ... } }`.
public enum BriefSection {
    case person(PersonData)
    case timeline(TimelineData)
    case prediction(PredictionData)
    case materials(MaterialsData)
    case options(OptionsData)
    case tactical(TacticalData)
    case quote(QuoteData)
    case watcher(WatcherSectionData)
    case diff(DiffData)
    case action(ActionData)
    /// Fallback — used when the JSON had a kind we don't recognise. The
    /// renderer paints a FallbackSection for these and logs the kind name.
    case unknown(String, [String: String]?)

    public var kind: BriefSectionKind? {
        switch self {
        case .person:     return .person
        case .timeline:   return .timeline
        case .prediction: return .prediction
        case .materials:  return .materials
        case .options:    return .options
        case .tactical:   return .tactical
        case .quote:      return .quote
        case .watcher:    return .watcher
        case .diff:       return .diff
        case .action:     return .action
        case .unknown:    return nil
        }
    }
}

extension BriefSection: Codable {
    private enum CodingKeys: String, CodingKey { case kind, data }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kindRaw = try container.decode(String.self, forKey: .kind)
        guard let kind = BriefSectionKind(rawValue: kindRaw) else {
            self = .unknown(kindRaw, nil)
            return
        }
        switch kind {
        case .person:     self = .person(try container.decode(PersonData.self, forKey: .data))
        case .timeline:   self = .timeline(try container.decode(TimelineData.self, forKey: .data))
        case .prediction: self = .prediction(try container.decode(PredictionData.self, forKey: .data))
        case .materials:  self = .materials(try container.decode(MaterialsData.self, forKey: .data))
        case .options:    self = .options(try container.decode(OptionsData.self, forKey: .data))
        case .tactical:   self = .tactical(try container.decode(TacticalData.self, forKey: .data))
        case .quote:      self = .quote(try container.decode(QuoteData.self, forKey: .data))
        case .watcher:    self = .watcher(try container.decode(WatcherSectionData.self, forKey: .data))
        case .diff:       self = .diff(try container.decode(DiffData.self, forKey: .data))
        case .action:     self = .action(try container.decode(ActionData.self, forKey: .data))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .person(let d):     try container.encode("person",     forKey: .kind); try container.encode(d, forKey: .data)
        case .timeline(let d):   try container.encode("timeline",   forKey: .kind); try container.encode(d, forKey: .data)
        case .prediction(let d): try container.encode("prediction", forKey: .kind); try container.encode(d, forKey: .data)
        case .materials(let d):  try container.encode("materials",  forKey: .kind); try container.encode(d, forKey: .data)
        case .options(let d):    try container.encode("options",    forKey: .kind); try container.encode(d, forKey: .data)
        case .tactical(let d):   try container.encode("tactical",   forKey: .kind); try container.encode(d, forKey: .data)
        case .quote(let d):      try container.encode("quote",      forKey: .kind); try container.encode(d, forKey: .data)
        case .watcher(let d):    try container.encode("watcher",    forKey: .kind); try container.encode(d, forKey: .data)
        case .diff(let d):       try container.encode("diff",       forKey: .kind); try container.encode(d, forKey: .data)
        case .action(let d):     try container.encode("action",     forKey: .kind); try container.encode(d, forKey: .data)
        case .unknown(let k, _): try container.encode(k,            forKey: .kind)
        }
    }
}

// ─── data shapes ───────────────────────────────────────────────────

public struct PersonData: Codable {
    public let name: String
    public let role: String
    public let avatar: String
    public let facts: [String]
    public let mutual: [Mutual]?

    public struct Mutual: Codable, Identifiable {
        public var id: String { name + via }
        public let name: String
        public let via: String
    }
}

public struct TimelineData: Codable {
    public let title: String
    public let items: [Item]

    public struct Item: Codable, Identifiable {
        public var id: String { date + text }
        public let date: String
        public let text: String
        public let subtle: Bool?
    }
}

public struct PredictionData: Codable {
    public let title: String
    public let items: [Item]

    public struct Item: Codable, Identifiable {
        public var id: String { text }
        public let text: String
        public let confidence: Confidence
        public enum Confidence: String, Codable { case high, medium, low }
    }
}

public struct MaterialsData: Codable {
    public let title: String
    public let items: [Item]

    public struct Item: Codable, Identifiable {
        public var id: String { text }
        public let text: String
        public let ready: Bool
    }
}

public struct OptionsData: Codable {
    public let title: String
    public let items: [Item]

    public struct Item: Codable, Identifiable {
        public var id: String { label }
        public let label: String
        public let reasoning: String
        public let mark: String?
    }
}

public struct TacticalData: Codable {
    public let text: String
}

public struct QuoteData: Codable {
    public let text: String
    public let attribution: String
}

public struct WatcherSectionData: Codable {
    public let text: String
    public let cadence: String
    public let last: String?
}

public struct DiffData: Codable {
    public let title: String
    public let items: [Item]

    public struct Item: Codable, Identifiable {
        public var id: String { kind.rawValue + text }
        public let kind: Kind
        public let text: String
        public enum Kind: String, Codable { case added, removed, changed }
    }
}

public struct ActionData: Codable {
    public let primary: String
    public let secondary: [String]
}
