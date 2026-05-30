import Foundation
import EventKit
import os

/// Reads the device calendar via EventKit and maps events into the existing
/// `CalendarConnector.Event` shape — so the agent's `calendar_query` tool and the
/// signal pipeline light up from the user's *real* schedule instead of fixtures.
/// Read-only: Ayumi never edits the calendar (principle 1 — prepares, never acts).
enum EventKitCalendarSource {
    static let store = EKEventStore()
    static let log = Logger(subsystem: "com.atlas.app", category: "Calendar")

    static var isAuthorized: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17, *) { return s == .fullAccess }
        return s == .authorized
    }

    /// Request calendar access once (call at launch). No-op once decided.
    static func requestAccess() async {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        do {
            if #available(iOS 17, *) { _ = try await store.requestFullAccessToEvents() }
            else { _ = try await store.requestAccess(to: .event) }
        } catch {
            log.error("calendar access request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Upcoming events mapped into the connector shape (empty if unauthorized).
    static func events(daysAhead: Int = 14) -> [CalendarConnector.Event] {
        guard isAuthorized else { return [] }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) else { return [] }
        let pred = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let mapped = store.events(matching: pred).prefix(50).map { e -> CalendarConnector.Event in
            let duration: Int? = {
                guard let s = e.startDate, let en = e.endDate else { return nil }
                return max(0, Int(en.timeIntervalSince(s) / 60))
            }()
            return CalendarConnector.Event(
                externalId: "ekcal:" + (e.eventIdentifier ?? UUID().uuidString),
                title: e.title ?? "Untitled event",
                location: e.location,
                startOffsetSeconds: e.startDate.map { $0.timeIntervalSince(now) },
                durationMinutes: duration
            )
        }
        log.info("read \(mapped.count) real calendar event(s)")
        return Array(mapped)
    }

    #if DEBUG
    /// DEV: drop a test event into the calendar so the connector has something
    /// real to read (used by the `--seed-calendar` launch arg in screenshots).
    static func seedDevEvent() {
        guard isAuthorized, let cal = store.defaultCalendarForNewEvents else { return }
        let e = EKEvent(eventStore: store)
        e.title = "Karan — coffee at Blue Tokai"
        e.location = "Blue Tokai, Bandra"
        e.startDate = Date().addingTimeInterval(3 * 3600)
        e.endDate = Date().addingTimeInterval(4 * 3600)
        e.calendar = cal
        try? store.save(e, span: .thisEvent)
    }
    #endif
}
