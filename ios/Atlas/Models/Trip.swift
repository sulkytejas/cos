import Foundation

// ════════════════════════════════════════════════════════════════════
//  Trip.swift — view-model / DTO types for the Living Chapter (v0.7).
//
//  These are PLAIN Swift value types (Codable / Identifiable) — NOT
//  SwiftData `@Model`s. The chapter detail view renders off a `Trip`
//  assembled by `AtlasRepo` (seeded offline, server-backed later). The
//  canonical persisted chapter still lives in `Models/Chapter.swift`;
//  `Trip` is the *reasoning-made-visible* projection the design needs
//  (provenance, legs, spend breakdown, connectors, receipts, …).
//
//  Design source of truth: design_handoff_capture_and_chapter/README.md
//  §PART 2 + atlas-trip.css. Every field maps to a styled element there.
// ════════════════════════════════════════════════════════════════════

// MARK: - Provenance — "how Ayumi knows it"

/// The provenance chip on every fact (README: "always show provenance").
/// Maps to `.know.booked` / `.know.inferred` / `.know.live` in atlas-trip.css,
/// plus `.told` once the user has corrected it (highest authority).
enum Provenance: String, Codable, CaseIterable, Identifiable, Hashable {
    /// Solid green chip — known from a booking / inbox (`#d9e7d8` / `#16321e`).
    case booked
    /// Dashed teal chip — Ayumi's inference, transparent w/ dashed border.
    case inferred
    /// Teal chip — confirmed live by Maps / Health (`#e0f1f4` / `--teal-deep`).
    case live
    /// Dark chip — "you told me", set after a correction. Highest authority.
    case told

    var id: String { rawValue }

    /// The mono micro-label shown inside the chip (uppercased by the view).
    var label: String {
        switch self {
        case .booked:   return "booked"
        case .inferred: return "inferred"
        case .live:     return "live"
        case .told:     return "you told me"
        }
    }
}

// MARK: - Stop (a place on the route)

/// A stop on the trip's vertical timeline (`.stop` in atlas-trip.css).
struct Stop: Codable, Identifiable, Hashable {
    /// Stable stop id, e.g. "nainital" (distinct from leg ids, which are `leg-*`).
    let id: String
    /// Place name (serif display), e.g. "Rishikesh".
    var place: String
    /// Mono date label, e.g. "May 28 – Jun 1".
    var dates: String
    /// The full serif-italic note, shown when the stop is expanded.
    var note: String
    /// One-line italic summary shown when a past stop is collapsed (`.mini`).
    var mini: String
    /// Timeline state — drives the pin styling + collapse behaviour.
    var state: StopState
    /// All provenance chips that apply to this stop's facts.
    var provenance: [Provenance]
    /// Whether a `.done` (past) stop currently renders collapsed.
    /// `.here` / `.upcoming` are never collapsible (stay loud).
    var collapsed: Bool

    enum StopState: String, Codable, CaseIterable, Identifiable, Hashable {
        case done       // past — collapses to `.mini`
        case here       // current — pulsing teal pin, always expanded
        case upcoming   // future — hollow pin, always expanded
        var id: String { rawValue }
    }

    /// Only past stops collapse; the present + future stay fully expanded.
    var isCollapsible: Bool { state == .done }
}

// MARK: - Leg (the ground transport between two stops)

/// The leg between two stops (`.leg` in atlas-trip.css). Unbooked legs render
/// as suggestions (`.leg.suggest`) with profile-tuned reasoning + an action.
struct Leg: Codable, Identifiable, Hashable {
    /// Stable leg id, byte-matched to the server (`leg-<toStop>`, e.g.
    /// "leg-nainital" for Delhi→Nainital). The correction target keys off this.
    let id: String
    /// The transport mode line, e.g. "Overnight Volvo bus" / "Flew to Pantnagar".
    var mode: String
    /// Ayumi's reasoning — the italic "why" line. Profile-aware for suggestions
    /// ("you get carsick on switchbacks, I'd split it overnight at Bhuntar").
    var why: String
    /// Mono fare label, e.g. "₹4,900". Empty for an unpriced suggestion.
    var fare: String
    /// True once this leg is a known booking. False ⇒ rendered as a suggestion.
    var booked: Bool
    /// The id of the upstream stop.
    var fromStop: String
    /// The id of the downstream stop.
    var toStop: String
    /// Set once the user has corrected this leg — flips it to the `.told` style.
    var corrected: Bool

    init(
        id: String, mode: String, why: String, fare: String,
        booked: Bool, fromStop: String, toStop: String, corrected: Bool = false
    ) {
        self.id = id; self.mode = mode; self.why = why; self.fare = fare
        self.booked = booked; self.fromStop = fromStop; self.toStop = toStop
        self.corrected = corrected
    }

    /// A suggested (unbooked) leg shows `Options` / `Hold seat` instead of a fare.
    var isSuggestion: Bool { !booked }
}

// MARK: - Spend (the "spent so far" panel)

/// The spend panel: a big number, a stacked segment bar, a legend, and a note on
/// where each number came from (`.spend-*` in atlas-trip.css).
struct Spend: Codable, Hashable {
    /// Amount spent so far in whole rupees, e.g. 34_750.
    var total: Int
    /// Projected end-of-trip total, e.g. 68_000.
    var projected: Int
    /// The four stacked segments (whole rupees) — order = bar order.
    var segments: Segments
    /// One sentence per source line: where the numbers came from + what is
    /// deliberately NOT counted yet (the two unbooked legs).
    var sources: [String]

    struct Segments: Codable, Hashable {
        var flights: Int   // `.s-flight` (forest)
        var stays: Int     // `.s-stay`   (teal)
        var food: Int      // `.s-food`   (sand)
        var travel: Int    // `.s-misc`   (ink-4) — ground travel
    }

    /// The currency symbol used throughout the chapter.
    static let currency = "₹"
}

// MARK: - Recommendation ("you'd love, near you")

/// A recommendation card, justified by a taste signal (`.rec` in atlas-trip.css).
struct Recommendation: Codable, Identifiable, Hashable {
    let id: String
    /// Place name (serif), e.g. "Blue Tokai".
    var text: String
    /// Mono sub-label — the locality, e.g. "RISHIKESH · 400M AWAY".
    var place: String
    /// The italic "why" line; the taste-signal phrase is emphasised in teal by
    /// the view, e.g. "you rate specialty coffee everywhere — Blue Tokai is your
    /// most-visited place".
    var tasteSignal: String
    /// Which thumbnail gradient to use (`.r1` / `.r2` / `.r3`).
    var thumb: String
}

// MARK: - Tracking ("tracking, live")

/// One stat card in the live-tracking grid (`.tcard` in atlas-trip.css).
struct TrackingStat: Codable, Identifiable, Hashable {
    let id: String
    /// Mono micro-label, e.g. "PLACES VISITED".
    var label: String
    /// The big serif value, e.g. "2" / "11.4k".
    var value: String
    /// Optional small unit appended after the value, e.g. "of 5" / "steps".
    var unit: String?
    /// Mono sub-line under the value.
    var sub: String
    /// Visual kind — drives whether dots / a sparkline / nothing renders.
    var kind: Kind
    /// Progress dots (places visited): one entry per slot.
    var dots: [DotState]
    /// Sparkline bar heights 0...1 (today's steps), with `dim` bars muted.
    var bars: [BarSample]
    /// Whether this card spans the full grid width (`.tcard.wide`).
    var wide: Bool

    enum Kind: String, Codable, Hashable { case plain, dots, bars }
    enum DotState: String, Codable, Hashable { case off, on, here }
    struct BarSample: Codable, Hashable { var height: Double; var dim: Bool }

    init(
        id: String, label: String, value: String, unit: String? = nil,
        sub: String, kind: Kind = .plain,
        dots: [DotState] = [], bars: [BarSample] = [], wide: Bool = false
    ) {
        self.id = id; self.label = label; self.value = value; self.unit = unit
        self.sub = sub; self.kind = kind; self.dots = dots; self.bars = bars
        self.wide = wide
    }
}

// MARK: - Connector ("to serve you better")

/// A data source Ayumi is using or would reach for next (`.conn` in atlas-trip.css).
/// Granting one flips `status` → `.feeding`, rewrites `role`, and blooms the halo.
struct Connector: Codable, Identifiable, Hashable {
    /// Stable id, e.g. "gmail" / "hdfc" / "irctc" / "calendar".
    let id: String
    /// Display name, e.g. "Gmail" / "HDFC card".
    var name: String
    /// The italic role line — what Ayumi does with it *now* (when feeding) or the
    /// neutral description (when available).
    var role: String
    /// `.feeding` (already in use, jade pulse) vs `.available` (offer a Connect).
    var status: Status
    /// One concrete line stating exactly what connecting it would unlock. Shown
    /// for `.available` as the pre-grant OFFER.
    var unlockCopy: String
    /// The POST-grant role — "what Ayumi can now do" (mirrors the server's
    /// `grantCopyFor`). Shown after granting instead of reusing the pre-grant
    /// offer copy. Empty for already-feeding sources (their `role` is already current).
    var grantedRole: String
    /// Which icon swatch to use (`.gmail` / `.health` / `.maps` / `.bank` / `.rail` / `.cal`).
    var icon: String

    enum Status: String, Codable, CaseIterable, Identifiable, Hashable {
        case feeding     // already wired in — live "Feeding" indicator
        case available   // offered — shows a Connect button + unlock copy
        var id: String { rawValue }
    }

    init(
        id: String, name: String, role: String, status: Status,
        unlockCopy: String, grantedRole: String = "", icon: String
    ) {
        self.id = id; self.name = name; self.role = role; self.status = status
        self.unlockCopy = unlockCopy; self.grantedRole = grantedRole; self.icon = icon
    }
}

// MARK: - Receipt ("how I built this")

/// One source row in a receipt sheet (`.receipt-card .src-row` in atlas-trip.css).
/// Named `TripReceipt` to avoid colliding with the Brief screen's `Receipt`.
struct TripReceipt: Codable, Identifiable, Hashable {
    let id: String
    /// Mono kind label, e.g. "EMAIL" / "CARD SWIPE" / "SEARCH" / "HEALTH".
    var kind: String
    /// The serif reference line, e.g. "IndiGo 6E-2043 · DEL→DEL · 18 May".
    var ref: String
    /// Which icon swatch (`.email` / `.card` / `.search` / `.health` / `.voice`).
    var icon: String
}

// MARK: - BuildStep (the receipts thread / provenance chain)

/// One node in the "how I built this" thread (`.bi` in atlas-trip.css): the chain
/// from one email → inference → live confirmation.
struct BuildStep: Codable, Identifiable, Hashable {
    let id: String
    /// Mono source label, e.g. "GMAIL · 18 MAY".
    var src: String
    /// The serif body; the view emphasises the `<b>` accent.
    var text: String
    /// True ⇒ hollow node dot (`.bi.inferred`), an inference rather than a fact.
    var inferred: Bool
}

// MARK: - Correction (quick "no, I took the bus" → reconcile)

/// A correction launched from a past leg/stop's pencil button (`.correct-*`).
/// Submitting one reconciles downstream (patches the leg, animates spend,
/// rebalances the legend) and emits a ripple {changed, learned}.
struct Correction: Codable, Identifiable, Hashable {
    let id: String
    /// The LEG id this correction targets (`leg-*`, byte-matched to the server,
    /// e.g. "leg-nainital"). The reconcile + collapse logic keys off the leg.
    var targetId: String
    /// The "what I assumed" line, pre-loaded with Ayumi's current belief.
    var assumed: String
    /// Quick-answer chips for the common cases.
    var options: [Option]
    /// Free-text placeholder for the user's own words.
    var freeTextPlaceholder: String

    struct Option: Codable, Identifiable, Hashable {
        let id: String
        /// Chip label, e.g. "Overnight Volvo bus".
        var label: String
    }
}

/// The result of reconciling a correction (README §A): what visibly changed and
/// the preference Ayumi learned (which tunes the *next* suggestion).
struct Ripple: Codable, Hashable {
    /// e.g. "Delhi → Nainital is now the overnight bus · spend ₹34,750 → ₹31,000".
    var changed: String
    /// The "what I learned" line, e.g. "you chose the bus over the flight — I'll
    /// lead with sleepers on your Kasol leg too."
    var learned: String
}

// MARK: - Trip (the whole Living Chapter projection)

/// The full chapter projection the detail view renders (README STATE MODEL).
struct Trip: Codable, Identifiable, Hashable {
    /// The chapter id (string form of the persisted `Chapter.id` when wired).
    let id: String
    /// Display title, e.g. "North India".
    var title: String
    /// Mono date-range + sub-line, e.g. "18–30 May · 5 stops · day 5".
    var dateRange: String
    /// The mono meta line under the avatar, e.g. "built from 1 email · watching 4 sources".
    var meta: String
    /// The serif-italic framing sentence; the view highlights the teal accent.
    var framing: String
    /// Optional explicit accent substring inside `framing` to teal-highlight.
    var framingAccent: String?

    var stops: [Stop]
    var legs: [Leg]
    var spend: Spend
    var recommendations: [Recommendation]
    var tracking: [TrackingStat]
    var connectors: [Connector]
    var receipts: [TripReceipt]
    /// The provenance-chain thread for "how I built this".
    var buildSteps: [BuildStep]
    /// Corrections available, keyed by the leg/stop they target.
    var corrections: [Correction]

    /// The leg targeted by a given correction id, if any.
    func leg(for legId: String) -> Leg? { legs.first { $0.id == legId } }
    /// The correction prepared for a given leg/stop id, if any.
    func correction(forTarget id: String) -> Correction? {
        corrections.first { $0.targetId == id }
    }
}
