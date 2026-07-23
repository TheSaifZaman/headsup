import AppKit
import EventKit

@MainActor
final class CalendarManager {
    private let store = EKEventStore()
    private(set) var hasAccess = false

    func requestAccess() async -> Bool {
        do {
            hasAccess = try await store.requestFullAccessToEvents()
        } catch {
            hasAccess = false
        }
        return hasAccess
    }

    func calendars() -> [EKCalendar] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    /// Events from enabled calendars inside `window`, as database records.
    func fetchStoredEvents(window: DateInterval) -> [StoredEvent] {
        guard hasAccess else { return [] }
        let disabled = AppSettings.shared.disabledCalendarIDs
        let enabledCalendars = store.calendars(for: .event)
            .filter { !disabled.contains($0.calendarIdentifier) }
        guard !enabledCalendars.isEmpty else { return [] }

        let ignoreDeclined = AppSettings.shared.ignoreDeclinedEvents
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: enabledCalendars)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .filter { ekEvent in
                guard ignoreDeclined,
                      let attendees = ekEvent.attendees,
                      let me = attendees.first(where: { $0.isCurrentUser }) else { return true }
                return me.participantStatus != .declined
            }
            .compactMap { ekEvent in
                guard let start = ekEvent.startDate, let end = ekEvent.endDate else { return nil }
                let identifier = ekEvent.eventIdentifier ?? UUID().uuidString
                return StoredEvent(
                    id: "apple-\(identifier)-\(Int(start.timeIntervalSince1970))",
                    title: ekEvent.title ?? "Untitled Event",
                    start: start,
                    end: end,
                    isAllDay: ekEvent.isAllDay,
                    source: .apple,
                    calendarName: ekEvent.calendar?.title ?? "Calendar",
                    colorHex: (ekEvent.calendar?.color ?? .systemBlue).hexString,
                    meetingLink: MeetingLinks.detect(in: ekEvent)?.absoluteString,
                    notes: ekEvent.notes,
                    subscriptionID: nil,
                    dismissedAt: nil
                )
            }
    }

    /// Writes a reminder into Apple Calendar (arrives back via sync).
    func createEvent(title: String, start: Date, urlString: String?) {
        guard hasAccess else { return }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(30 * 60)
        event.calendar = store.defaultCalendarForNewEvents
        if let urlString, let url = URL(string: urlString) {
            event.url = url
        }
        try? store.save(event, span: .thisEvent)
    }
}
