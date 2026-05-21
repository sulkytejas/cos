import Foundation

/// Morning page — Atlas drafts one paragraph in your voice every morning,
/// from the overnight signals. v0.2 ships this as a static seed; v0.3
/// replaces it with the daily-scan worker's output.
struct MorningPageData: Codable {
    let range: String     // "02:14 → 06:38"
    let draftedAt: String // "06:38"
    var sentences: [MorningSentenceData]
}

struct MorningSentenceData: Codable, Identifiable {
    let id: String
    let text: String
    /// Hint at which chapter the extracts would land in. Matches the iOS app
    /// chapter title prefix (e.g. "Stratyfix", "Ireland", "Varanasi", "Health").
    let chapterHint: String?
    let extracts: Extracts?

    struct Extracts: Codable {
        let todo: Int?
        let decision: Int?
        let journal: Int?
    }
}

let SEEDED_MORNING_PAGE = MorningPageData(
    range: "02:14 → 06:38",
    draftedAt: "06:38",
    sentences: [
        MorningSentenceData(
            id: "s1",
            text: "It was a long night.",
            chapterHint: nil,
            extracts: nil
        ),
        MorningSentenceData(
            id: "s2",
            text: "Karan asked for retention numbers by Tuesday — added that to the list.",
            chapterHint: "Stratyfix",
            extracts: .init(todo: 1, decision: nil, journal: nil)
        ),
        MorningSentenceData(
            id: "s3",
            text: "Three small things for the trip: Volvo sleeper to Manali, offline maps for the valley, and cash past Kasol where the ATMs go sparse.",
            chapterHint: "Varanasi",
            extracts: .init(todo: 3, decision: nil, journal: nil)
        ),
        MorningSentenceData(
            id: "s4",
            text: "Trinity over UCD — I'd been holding that since April but only said it on yesterday's walk; the network argument tips the balance.",
            chapterHint: "Ireland",
            extracts: .init(todo: nil, decision: 1, journal: nil)
        ),
        MorningSentenceData(
            id: "s5",
            text: "Came back to \"irreversibility\" three times thinking about V.'s objections — that's the real worry, not the burn.",
            chapterHint: "Stratyfix",
            extracts: .init(todo: nil, decision: nil, journal: 1)
        ),
        MorningSentenceData(
            id: "s6",
            text: "The ARR slide is taking a lot of energy — 14 edits in a week. Noting it, though I'm unsure whether it's a signal or just the deck eating my Tuesdays.",
            chapterHint: "Stratyfix",
            extracts: .init(todo: nil, decision: nil, journal: 1)
        ),
    ]
)
