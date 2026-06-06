import Foundation
import Observation

// ════════════════════════════════════════════════════════════════════
//  CaptureTypes.swift — the Capture co-completion state machine (v0.7).
//
//  Capture is NOT a screen. It is Ayumi, summoned in place over whatever
//  surface you're on: a teal cue at the foot of every screen rises into a
//  co-completion "well". You hand Ayumi a *fragment* (typed or spoken); it's
//  ghost-completed into a structured note + a forming tag, or Ayumi asks one
//  sharp question when it can't complete confidently.
//
//  This file owns the STATE + a `CaptureController` (@Observable @MainActor)
//  with the actions the UI binds to. It calls `AtlasRepo` for real
//  completion/filing, and degrades to a small seeded dictionary offline.
//
//  Design source of truth: design_handoff_capture_and_chapter/README.md
//  §PART 1 + atlas-capture.css / atlas-capture.js.
// ════════════════════════════════════════════════════════════════════

// MARK: - Capture value types

/// The kind of structure Ayumi forms from a fragment (the lightweight
/// classifier output): a todo, a decision, or a note.
enum CoCaptureKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case todo
    case decision
    case note

    var id: String { rawValue }
    var label: String { rawValue }
}

/// Which input the well is in (`atlas-capture.js` `state.mode`).
enum CaptureMode: String, Codable, Hashable {
    case text
    case voice
}

/// The voice-duet behaviour, exposed as a toggle (README §"Voice duet"):
/// `.settle` — transcript becomes editable, user taps Send;
/// `.handsfree` — auto-sends on stop.
enum VoiceBehavior: String, Codable, CaseIterable, Identifiable, Hashable {
    case settle
    case handsfree

    var id: String { rawValue }
    var label: String {
        switch self {
        case .settle:    return "Settle to text"
        case .handsfree: return "Hands-free"
        }
    }
}

/// What Ayumi is forming — the classifier match shown as the forming tag and
/// used when filing (README STATE MODEL: `match: {kind, chapterId}`).
struct CaptureMatch: Codable, Hashable {
    var kind: CoCaptureKind
    /// Which chapter this files into (nil ⇒ auto-file to the right thread).
    var chapterId: String?
    /// The forming-tag suffix shown after the kind, e.g. "Stratyfix · due Tue".
    var tag: String
    /// True for the generic "I'll file this under the right thread." fallback.
    var generic: Bool

    init(kind: CoCaptureKind, chapterId: String? = nil, tag: String, generic: Bool = false) {
        self.kind = kind; self.chapterId = chapterId; self.tag = tag; self.generic = generic
    }

    /// The forming-tag value, e.g. "todo · Stratyfix · due Tue" or "note · auto-filed".
    var formingLabel: String {
        generic ? "note · auto-filed" : "\(kind.rawValue) · \(tag)"
    }
}

/// The single low-confidence question (README §"A one-question card").
struct CaptureQuestion: Codable, Hashable {
    var text: String
    /// Two answer chips (plus an implicit `ignore` rendered by the view).
    var answers: [String]
}

/// One completion entry in the offline co-completion dictionary
/// (`atlas-capture.js` `PREDICTIONS`): a full completion + the structure +
/// the optional one-question.
struct CapturePrediction: Codable, Hashable {
    /// The full sentence the fragment ghost-completes into.
    var full: String
    var kind: CoCaptureKind
    var chapterId: String?
    /// The forming-tag suffix.
    var tag: String
    /// The single question to ask before filing, if confidence is low.
    var question: CaptureQuestion?
}

/// The result of asking the backend (or the dictionary) to complete a fragment.
struct CaptureCompletion: Hashable {
    /// The remainder to render as ghost text (empty ⇒ no confident match).
    var ghost: String
    /// The forming structure, if matched.
    var match: CaptureMatch?
    /// The single question to ask before filing, if confidence is low.
    var question: CaptureQuestion?

    static let none = CaptureCompletion(ghost: "", match: nil, question: nil)
}

// MARK: - CaptureController

/// The Capture state machine + actions the UI binds to. `@Observable` so the
/// global cue/sheet re-renders on every field change; `@MainActor` because it
/// drives presence (the halo) and owns user-facing state.
///
/// The controller calls `AtlasRepo` for real completion/classification + filing,
/// and falls back to the seeded dictionary when offline / unconfigured — so the
/// well co-completes faithfully with no network.
@MainActor
@Observable
final class CaptureController {

    // ── Observed state (README STATE MODEL "Capture") ──────────────────
    /// Whether the well is summoned.
    private(set) var open = false
    /// Text vs voice input.
    private(set) var mode: CaptureMode = .text
    /// The solid (committed) text the user has typed / accepted.
    private(set) var draft = ""
    /// The italic ghost remainder Ayumi is offering (`--ink-4`).
    private(set) var ghost = ""
    /// The forming structure, once matched.
    private(set) var match: CaptureMatch?
    /// True once the ghost has been committed into solid ink (tag locked).
    private(set) var locked = false
    /// The single low-confidence question, when shown.
    private(set) var question: CaptureQuestion?
    /// The pending low-confidence question the LAST completion produced (server or
    /// dictionary), held until capture surfaces it. Kept separate from `question`
    /// (which is the *shown* card) so an arbitrary server-completed fragment can
    /// still ask — the offline dictionary only prefix-matches the 5 seeded entries.
    @ObservationIgnored private var pendingQ: CaptureQuestion?
    /// The voice-duet behaviour toggle.
    var voiceBehavior: VoiceBehavior = .settle
    /// Whether the mic is live (drives the pulsing-forest mic + PenLine).
    private(set) var micLive = false
    /// The screen name the well was summoned over ("Capturing — over <Screen>").
    private(set) var overScreen = "Today"
    /// The terminal "Kept." state — the sheet shows the filed structure then
    /// auto-closes (README §"A filed state").
    private(set) var filed: FiledState?
    /// True while a streaming completion / file mutation is in flight.
    private(set) var busy = false

    /// What the filed confirmation shows (structure filed + an optional answer).
    struct FiledState: Hashable {
        var headline: String           // "Kept."
        var sub: String                // where it landed
        var tags: [String]             // the filed structure chips
    }

    // ── Dependencies ──────────────────────────────────────────────────
    /// The repo for real completion + filing. Optional so the controller is
    /// constructible in previews / before the environment is available.
    @ObservationIgnored private weak var repo: AtlasRepo?
    /// Presence bridge — the host screen's halo. A closure so the controller
    /// doesn't import the view layer (README: "drive the same presence animation").
    @ObservationIgnored var onHaloState: ((HaloController.HaloState) -> Void)?

    /// Whether a confident ghost is currently offered (for the accept hint).
    var hasGhost: Bool { !ghost.isEmpty && !locked }
    /// Whether the Capture button should be enabled.
    var canCapture: Bool { !draft.isEmpty || locked || mode == .voice }

    init(repo: AtlasRepo? = nil) {
        self.repo = repo
    }

    func attach(repo: AtlasRepo) { self.repo = repo }

    // MARK: - View-driven setters
    //
    // The well's render is a styled composite of `draft` + `ghost`, so the view
    // layer needs to set these directly (e.g. applying the structure Ayumi forms
    // at the end of the voice duet). Kept minimal + intentional.

    /// Set the committed draft text directly (voice transcript → editable draft).
    func setDraft(_ text: String) { draft = text }

    /// Set the forming match directly (the voice duet's end-of-speech structure).
    func setMatch(_ match: CaptureMatch?) { self.match = match }

    /// DEBUG: open the well pre-seeded with a fragment + its completion, so the
    /// `--capture` launch arg lands on a faithful co-completion state for
    /// screenshot verification.
    func debugOpen(over screen: String, seed fragment: String) async {
        open(over: screen)
        await onType(fragment)
    }

    // MARK: - Open / close

    /// Summon the well over `screen`, resetting all transient state.
    func open(over screen: String) {
        overScreen = screen
        open = true
        reset()
    }

    /// Return to the host screen exactly where the user was (Esc / swipe-down /
    /// tap-outside). Settles the halo back to idle.
    func close() {
        guard open else { return }
        open = false
        stopVoice()
        onHaloState?(.idle)
    }

    /// Clear the well to its empty state (keeps it open).
    private func reset() {
        mode = .text
        draft = ""
        ghost = ""
        match = nil
        locked = false
        question = nil
        pendingQ = nil
        micLive = false
        filed = nil
        busy = false
    }

    // MARK: - Typing → ghost + forming tag

    /// The user typed; recompute the ghost + forming tag from the fragment.
    /// Co-completion (README §"Co-completion model"): real backend = streaming
    /// completion + classifier; offline = the seeded dictionary.
    func onType(_ fragment: String) async {
        locked = false
        draft = fragment
        let completion = await complete(fragment)
        // A late completion must not clobber a draft the user has since changed.
        guard draft == fragment else { return }
        ghost = completion.ghost
        match = completion.match
        // Hold this completion's low-confidence question until capture surfaces it.
        // Stored here (not just the dictionary) so a SERVER-completed fragment —
        // which won't prefix-match any seeded dictionary entry — can still ask its
        // one question on the real backend.
        pendingQ = completion.question
    }

    /// Resolve a fragment to a completion: try the repo, fall back to the dict.
    private func complete(_ fragment: String) async -> CaptureCompletion {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return .none }
        if let repo {
            let r = await repo.completeCapture(trimmed)
            if let kind = CoCaptureKind(rawValue: r.kind) {
                let m = CaptureMatch(kind: kind, chapterId: r.chapterId, tag: r.tag,
                                     generic: r.generic)
                return CaptureCompletion(ghost: r.ghost, match: m, question: r.question)
            }
            // Repo couldn't classify (e.g. offline → no match) — fall through.
        }
        return Self.dictionaryCompletion(for: trimmed)
    }

    // MARK: - Commit / lock the ghost

    /// Tab (or tapping the ghost): commit the ghost into solid ink + lock the tag
    /// (README §"Co-completion model").
    func commitGhost() {
        guard hasGhost else { return }
        draft += ghost
        ghost = ""
        locked = true
    }

    // MARK: - One question

    /// Surface the single low-confidence question (README §"A one-question card").
    func askQuestion(_ q: CaptureQuestion) {
        question = q
    }

    /// Dismiss the question without answering ("ignore").
    func ignoreQuestion() {
        question = nil
    }

    // MARK: - Voice duet

    /// Toggle the mic. Entering voice switches the well to the voice duet
    /// (PenLine + teal interjections); the halo goes `thinking`.
    func toggleMic() {
        if mode == .voice { stopVoice(); return }
        mode = .voice
        micLive = true
        draft = ""
        ghost = ""
        locked = false
        question = nil
        pendingQ = nil
        onHaloState?(.thinking)
    }

    /// Stop voice input and return to text. If hands-free, the caller files.
    func stopVoice() {
        micLive = false
        if mode == .voice { mode = .text }
    }

    // MARK: - File (the terminal capture)

    /// File the capture. The well's items "fly" to the cue, the halo goes
    /// thinking → delivered, "Kept." shows the filed structure, then the sheet
    /// auto-closes (the caller schedules `close()` after ~1.7s).
    ///
    /// Real backend: a "file note" mutation (`repo.fileCapture`). Offline: the
    /// optimistic local file stands and the structure is still confirmed.
    @discardableResult
    func file(answer: String? = nil) async -> FiledState {
        // If a low-confidence question is pending and unanswered, surface it
        // first (one capture-press asks, the next files) — handled by callers
        // that route through `capturePressed`. Here we just file.
        busy = true
        onHaloState?(.thinking)

        let kind = match?.kind ?? .note
        let chapterId = match?.chapterId
        let text = (draft + ghost).trimmingCharacters(in: .whitespacesAndNewlines)

        await repo?.fileCapture(text: text, kind: kind.rawValue,
                                chapterId: chapterId, answer: answer,
                                source: mode == .voice ? "voice" : "text")

        let tagSuffix = match?.tag ?? "auto-filed"
        var tags = [match?.generic == true ? "note · auto-filed" : "\(kind.rawValue) · \(tagSuffix)"]
        if let answer { tags.append("you said: \(answer.lowercased())") }

        let state = FiledState(
            headline: "Kept.",
            sub: mode == .voice
                ? Self.voiceFiledSub(match: match, transcript: text)
                : "Filed to the right thread. It’s waiting for you where it belongs.",
            tags: tags
        )
        filed = state
        busy = false
        onHaloState?(.delivered)
        return state
    }

    /// The specific, reasoning-legible voice "Kept." sub-line (README/proto:
    /// "Your thought is in the Stratyfix thread. I'll bring the runway math to your
    /// next brief."). Derives the THREAD name from the match's tag/chapterId and
    /// the SUBJECT from the transcript, so the line stays specific rather than a
    /// generic "the right thread"; falls back gracefully when either is unknown.
    static func voiceFiledSub(match: CaptureMatch?, transcript: String) -> String {
        let thread = threadName(from: match)
        let subject = subjectPhrase(from: transcript)
        let where_ = thread.map { "in the \($0) thread" } ?? "in the right thread"
        let bring = subject.map { "bring the \($0) to" } ?? "bring it to"
        return "Your thought is \(where_). I’ll \(bring) your next brief."
    }

    /// The display thread name for the filed match — the chapter title when known,
    /// else the leading token of the forming tag (e.g. "Stratyfix · journal" →
    /// "Stratyfix"). Nil when the note auto-files at the top level.
    private static func threadName(from match: CaptureMatch?) -> String? {
        guard let match, !match.generic else { return nil }
        if let lead = match.tag.split(separator: "·").first?
            .trimmingCharacters(in: .whitespaces), !lead.isEmpty {
            return lead
        }
        return match.chapterId?.capitalized
    }

    /// A short subject phrase pulled from the transcript — the noun the brief will
    /// "bring" (e.g. "…the runway math is tighter…" → "runway math"). Best-effort:
    /// nil when nothing salient is found, so the copy falls back to "bring it".
    private static func subjectPhrase(from transcript: String) -> String? {
        let lo = transcript.lowercased()
        // A small set of salient subjects the demo speaks to; first hit wins.
        let known = ["runway math", "runway", "side-letter", "retention", "runway number"]
        for k in known where lo.contains(k) { return k }
        return nil
    }

    /// The Capture button / Enter. If a question is pending and unanswered, ask
    /// it first (commit any ghost); otherwise file. Returns true if it filed.
    @discardableResult
    func capturePressed() async -> Bool {
        // Text path: if the match carries an unanswered question, ask it once.
        if mode == .text, question == nil,
           let q = pendingQuestion(), filed == nil {
            commitGhost()
            askQuestion(q)
            return false
        }
        await file()
        return true
    }

    /// Answer the question's chip — files with that answer attached.
    @discardableResult
    func answerQuestion(_ answer: String) async -> FiledState {
        question = nil
        return await file(answer: answer)
    }

    /// The question the current match would ask, if any. Prefer the question the
    /// last completion produced (works for ANY server-completed fragment); fall
    /// back to re-matching the dictionary for the offline/voice scripted paths.
    private func pendingQuestion() -> CaptureQuestion? {
        guard let match, !match.generic else { return nil }
        return pendingQ ?? Self.dictionaryCompletion(for: draft).question
    }

    // MARK: - Offline co-completion dictionary
    //
    // Mirrors `atlas-capture.js` PREDICTIONS: type the start of any entry and
    // Ayumi ghosts the remainder + the forming structure. With a real backend
    // this is replaced by a streaming completion + a classifier.

    static let predictions: [CapturePrediction] = [
        CapturePrediction(
            full: "Karan wants retention by Tuesday — pull the M6 cohort and send it ahead of the 2:30.",
            kind: .todo, chapterId: "stratyfix", tag: "Stratyfix · due Tue",
            question: CaptureQuestion(text: "Send it before the call, or wait for his nudge?",
                                      answers: ["Send ahead", "Wait"])
        ),
        CapturePrediction(
            full: "Remind me to ask V. about moving the studio sitting to 11:30 — the light’s better.",
            kind: .todo, chapterId: nil, tag: "today", question: nil
        ),
        CapturePrediction(
            full: "I think we should drop the IP side-letter if it slows the close.",
            kind: .decision, chapterId: "stratyfix", tag: "Stratyfix",
            question: CaptureQuestion(text: "Is the side-letter a hard no, or negotiable if he pushes?",
                                      answers: ["Hard no", "Negotiable"])
        ),
        CapturePrediction(
            full: "Worried the runway is tighter than we’re saying — maybe nine months, not twelve.",
            kind: .note, chapterId: "stratyfix", tag: "Stratyfix · journal",
            question: CaptureQuestion(text: "Want the real runway number worked out and put in the brief?",
                                      answers: ["Yes, add it", "Not now"])
        ),
        CapturePrediction(
            full: "Book the Volvo sleeper to Manali and grab offline maps for the valley.",
            kind: .todo, chapterId: "north", tag: "North India · 2 todos", question: nil
        ),
    ]

    /// Match a fragment against the dictionary — prefix match like the prototype,
    /// with a generic auto-file fallback once the fragment is long enough.
    static func dictionaryCompletion(for fragment: String) -> CaptureCompletion {
        let lo = fragment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lo.count >= 4 else { return .none }
        for p in predictions where p.full.lowercased().hasPrefix(lo) {
            let ghost = String(p.full.dropFirst(fragment.count))
            let m = CaptureMatch(kind: p.kind, chapterId: p.chapterId, tag: p.tag)
            return CaptureCompletion(ghost: ghost, match: m, question: p.question)
        }
        if lo.count >= 12 {
            return CaptureCompletion(
                ghost: " — I’ll file this under the right thread.",
                match: CaptureMatch(kind: .note, tag: "auto-filed", generic: true),
                question: nil
            )
        }
        return .none
    }
}
