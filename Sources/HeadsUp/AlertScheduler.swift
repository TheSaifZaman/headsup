import AppKit
import Foundation

@MainActor
final class AlertScheduler {
    private let db = Database.shared
    let alerts = AlertController()
    let preAlerts = PreAlertController()

    /// Events that already fired an alert this session.
    private var handled = Set<String>()
    /// Snoozed events re-fire once the date passes.
    private var snoozes: [String: Date] = [:]
    /// Pre-alert pills the user closed.
    private var preAlertDismissed = Set<String>()
    /// Meetings already auto-joined this session.
    private var autoJoined = Set<String>()

    /// Alertable events: not ended, not all-day, and (for reminders) not
    /// already dismissed. Soonest first.
    var upcoming: [StoredEvent] {
        let now = Date()
        return db.events
            .filter { $0.end > now && !$0.isAllDay }
            .filter { !($0.source == .manual && $0.dismissedAt != nil) }
            .sorted { $0.start < $1.start }
    }

    var nextEvent: StoredEvent? { upcoming.first }

    // MARK: - Tick

    func tick() {
        let now = Date()
        advanceMissedRepeatingReminders(now: now)
        autoJoinIfDue(now: now)
        fireAlertIfNeeded(now: now)
        updatePreAlert(now: now)
    }

    // MARK: - Full-screen alerts

    private func alertWindow(for event: StoredEvent) -> TimeInterval {
        // Reminders fire at their exact time; meetings fire leadTime early.
        event.source == .manual ? 0 : TimeInterval(AppSettings.shared.leadTimeMinutes * 60)
    }

    private func fireAlertIfNeeded(now: Date) {
        guard !alerts.isShowing else { return }

        for event in upcoming {
            if handled.contains(event.id) {
                // Only re-fire if a snooze elapsed.
                guard let snoozeDate = snoozes[event.id], now >= snoozeDate else { continue }
            }
            guard event.start.timeIntervalSince(now) <= alertWindow(for: event) else { continue }
            show(event)
            break
        }
    }

    func show(_ event: StoredEvent) {
        handled.insert(event.id)
        snoozes.removeValue(forKey: event.id)
        preAlerts.dismiss()

        // Back-to-back awareness: another event starting within 5 minutes of
        // this one ending (or overlapping it).
        let followUp = upcoming.first {
            $0.id != event.id && $0.start >= event.start && $0.start <= event.end.addingTimeInterval(5 * 60)
        }

        alerts.show(event: event, followUp: followUp) { [weak self] action in
            guard let self else { return }
            switch action {
            case .snoozed(let minutes):
                self.snoozes[event.id] = Date().addingTimeInterval(TimeInterval(minutes * 60))
            case .snoozedUntilOneMinuteBefore:
                self.snoozes[event.id] = event.start.addingTimeInterval(-60)
            case .dismissed, .joined:
                if event.source == .manual {
                    if event.repeatRule != nil {
                        self.db.completeAndScheduleNext(id: event.id)
                    } else {
                        self.db.markDismissed(id: event.id)
                    }
                }
            }
        }
    }

    // MARK: - Pre-alert pill (stage one)

    private func updatePreAlert(now: Date) {
        let settings = AppSettings.shared
        guard settings.preAlertMinutes > 0, !alerts.isShowing else {
            preAlerts.dismiss()
            return
        }

        let candidate = upcoming.first { event in
            guard !preAlertDismissed.contains(event.id), !handled.contains(event.id) else { return false }
            let until = event.start.timeIntervalSince(now)
            return until > alertWindow(for: event) && until <= TimeInterval(settings.preAlertMinutes * 60)
        }

        if let candidate {
            preAlerts.show(event: candidate) { [weak self] in
                self?.preAlertDismissed.insert(candidate.id)
            }
        } else {
            preAlerts.dismiss()
        }
    }

    // MARK: - Auto-join

    private func autoJoinIfDue(now: Date) {
        guard AppSettings.shared.autoJoinMeetings else { return }
        for event in upcoming {
            guard let url = event.meetingURL, !autoJoined.contains(event.id) else { continue }
            let sinceStart = now.timeIntervalSince(event.start)
            guard sinceStart >= 0 && sinceStart < 60 else { continue }
            autoJoined.insert(event.id)
            NSWorkspace.shared.open(url)
            if alerts.currentEventID == event.id {
                alerts.dismiss()
            }
        }
    }

    // MARK: - Repeating reminders

    /// A repeating reminder that expired without being dismissed (Mac asleep,
    /// app closed…) still needs its next occurrence scheduled.
    private func advanceMissedRepeatingReminders(now: Date) {
        let missed = db.events.filter {
            $0.source == .manual && $0.repeatRule != nil && $0.dismissedAt == nil && $0.end < now
        }
        for event in missed {
            db.completeAndScheduleNext(id: event.id)
        }
    }

    // MARK: - Test alert

    /// Pass a user-supplied meeting link to test the Join button, or nil.
    func showTestAlert(meetingLink: String?) {
        let event = StoredEvent(
            id: "test-\(UUID().uuidString)",
            title: "Test Alert — you can't miss this",
            start: Date().addingTimeInterval(120),
            end: Date().addingTimeInterval(30 * 60),
            isAllDay: false,
            source: .apple,
            calendarName: "Heads Up",
            colorHex: "#FF3B30",
            meetingLink: meetingLink,
            notes: nil,
            subscriptionID: nil,
            dismissedAt: nil
        )
        alerts.show(event: event, followUp: nil) { _ in }
    }
}
