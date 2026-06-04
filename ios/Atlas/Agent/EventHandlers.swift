import Foundation

/// EventHandlers — NEUTRALIZED (SERVER_ARCHITECTURE.md §4.e).
///
/// The per-event agent handlers (capture / watcher-due / daily-scan /
/// signal-received / brief-acted-on / chapter-created), the `EventDispatcher`,
/// and the bundled Gmail/Drive/Calendar connector fixtures all ran the
/// on-device brain. That brain has moved to the SERVER worker (event processing,
/// connectors, and the agent loop now live in `worker/src/*` behind the
/// throttled gateway). The device no longer drains `AppEvent`s or runs the model.
///
/// The ONLY thing retained here is `CalendarConnector.Event` — the value shape
/// `EventKitCalendarSource` maps device-calendar events into before
/// `AtlasRepo.pushCalendarSignals()` sends them to the server as `calendar`
/// signals (the device-only push source, §4.e). Everything else is deleted.
enum CalendarConnector {
    /// The mapped shape of one device-calendar event. `EventKitCalendarSource`
    /// produces these; `AtlasRepo.pushCalendarSignals()` ingests them via
    /// `signal.ingest` (which upserts on `(source, externalId)`).
    struct Event: Codable {
        let externalId: String
        let title: String
        let location: String?
        let startOffsetSeconds: TimeInterval?
        let durationMinutes: Int?
    }
}
