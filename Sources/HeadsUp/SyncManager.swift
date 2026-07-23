import Foundation

/// Pulls events from Apple Calendar (EventKit) and ICS subscription URLs
/// (e.g. Google Calendar's secret iCal address) into the local database.
@MainActor
final class SyncManager: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?

    private let db = Database.shared
    private let calendarManager: CalendarManager

    /// Sync window: 30 days back (history) to 90 days ahead.
    nonisolated static func currentWindow() -> DateInterval {
        DateInterval(start: Date().addingTimeInterval(-30 * 86400), duration: 120 * 86400)
    }

    init(calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        let window = Self.currentWindow()

        if calendarManager.hasAccess {
            let appleEvents = calendarManager.fetchStoredEvents(window: window)
            db.replaceSynced(source: .apple, subscriptionID: nil, window: window, with: appleEvents)
        }

        for subscription in db.subscriptions {
            await sync(subscription, window: window)
        }

        db.prune()
    }

    func sync(_ subscription: ICSSubscription, window: DateInterval = SyncManager.currentWindow()) async {
        let urlString = subscription.url
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "webcal://", with: "https://")
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            lastError = "\(subscription.name): invalid URL"
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                lastError = "\(subscription.name): server returned \(http.statusCode)"
                return
            }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                lastError = "\(subscription.name): unreadable response"
                return
            }
            let parsed = ICSParser.parse(text, window: window)
            let events = parsed.map { item in
                StoredEvent(
                    id: "ics-\(subscription.id.uuidString)-\(item.uid)-\(Int(item.start.timeIntervalSince1970))",
                    title: item.title,
                    start: item.start,
                    end: item.end,
                    isAllDay: item.isAllDay,
                    source: .ics,
                    calendarName: subscription.name,
                    colorHex: subscription.colorHex,
                    meetingLink: MeetingLinks.detect(in: [item.urlString, item.location, item.notes].compactMap { $0 })?.absoluteString,
                    notes: item.notes,
                    subscriptionID: subscription.id,
                    dismissedAt: nil
                )
            }
            db.replaceSynced(source: .ics, subscriptionID: subscription.id, window: window, with: events)
            db.touchSubscription(id: subscription.id)
        } catch {
            lastError = "\(subscription.name): \(error.localizedDescription)"
        }
    }
}
