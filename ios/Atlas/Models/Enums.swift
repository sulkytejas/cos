import Foundation

enum ChapterType: String, Codable, CaseIterable, Identifiable {
    case trip
    case move
    case project
    case launch
    case recurring
    case personal

    var id: String { rawValue }

    var label: String { rawValue.uppercased() }

    var sfSymbol: String {
        switch self {
        case .trip: return "airplane"
        case .move: return "building.2"
        case .project: return "briefcase"
        case .launch: return "paperplane"
        case .recurring: return "arrow.triangle.2.circlepath"
        case .personal: return "circle"
        }
    }
}

enum ChapterStatus: String, Codable, CaseIterable, Identifiable {
    case upcoming
    case active
    case paused
    case done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .active: return "Active"
        case .paused: return "Paused"
        case .done: return "Done"
        }
    }

    var sortIndex: Int {
        switch self {
        case .active: return 0
        case .upcoming: return 1
        case .paused: return 2
        case .done: return 3
        }
    }
}

enum LinkRelation: String, Codable, CaseIterable, Identifiable {
    case blocks
    case enables
    case conflicts
    case related

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blocks: return "blocks"
        case .enables: return "enables"
        case .conflicts: return "conflicts with"
        case .related: return "related to"
        }
    }
}

enum EntrySource: String, Codable, CaseIterable {
    case manual
    case email
    case calendar
    case drive
}

enum TodoSource: String, Codable, CaseIterable {
    case manual
    case extracted
}
