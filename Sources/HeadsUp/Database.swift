import AppKit
import Foundation

// MARK: - Stored event (calendar event, ICS event, or manual reminder)

struct StoredEvent: Codable, Identifiable, Hashable {
    enum Source: String, Codable, Hashable {
        case manual   // reminder created in the app
        case apple    // synced from Apple Calendar (EventKit)
        case ics      // synced from an ICS subscription URL
    }

    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var source: Source
    var calendarName: String
    var colorHex: String
    var meetingLink: String?
    var notes: String?
    var subscriptionID: UUID?
    var dismissedAt: Date?
    /// Manual reminders only: "daily", "weekdays", or "weekly". nil = one-off.
    var repeatRule: String? = nil

    var meetingURL: URL? { meetingLink.flatMap(URL.init(string:)) }
    var color: NSColor { NSColor(hex: colorHex) }

    var repeatLabel: String? {
        switch repeatRule {
        case "daily": return "daily"
        case "weekdays": return "weekdays"
        case "weekly": return "weekly"
        default: return nil
        }
    }
}

// MARK: - ICS subscription (e.g. Google Calendar secret iCal address)

struct ICSSubscription: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var colorHex: String
    var lastSync: Date?
}

// MARK: - Database (self-contained JSON text file)

@MainActor
final class Database: ObservableObject {
    static let shared = Database()

    @Published private(set) var events: [StoredEvent] = []
    @Published private(set) var subscriptions: [ICSSubscription] = []
    /// Synced events the user deleted from the app — sync must not re-add them.
    private var hiddenIDs: Set<String> = []

    @Published private(set) var fileURL: URL

    private static let directoryKey = "databaseDirectory"

    static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HeadsUp", isDirectory: true)
    }

    var isAtDefaultLocation: Bool {
        fileURL.deletingLastPathComponent().path == Self.defaultDirectory.path
    }

    enum DatabaseError: LocalizedError {
        case writeFailed(String)
        var errorDescription: String? {
            if case .writeFailed(let path) = self {
                return "Could not write the database to \(path). The previous location is still in use."
            }
            return nil
        }
    }

    private struct FileFormat: Codable {
        var version: Int
        var events: [StoredEvent]
        var subscriptions: [ICSSubscription]
        var hiddenIDs: [String]?
    }

    private init() {
        let fm = FileManager.default
        var dir = Self.defaultDirectory
        // Honor a user-chosen folder, but fall back to the default if it's
        // unreachable (e.g. an unplugged external drive).
        if let customPath = UserDefaults.standard.string(forKey: Self.directoryKey) {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: customPath, isDirectory: &isDirectory), isDirectory.boolValue {
                dir = URL(fileURLWithPath: customPath, isDirectory: true)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.directoryKey)
            }
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("database.json")
        migrateLegacyDatabase()
        load()
        migrateLegacyReminders()
    }

    // MARK: Location

    /// Moves the database file to a new folder and uses it from now on.
    func relocate(to directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("database.json")
        guard destination.path != fileURL.path else { return }

        // Never clobber an existing file at the destination — back it up.
        if fm.fileExists(atPath: destination.path) {
            let backup = directory.appendingPathComponent("database-backup-\(Int(Date().timeIntervalSince1970)).json")
            try fm.moveItem(at: destination, to: backup)
        }

        let previousURL = fileURL
        fileURL = destination
        save()
        guard fm.fileExists(atPath: destination.path) else {
            fileURL = previousURL
            throw DatabaseError.writeFailed(destination.path)
        }
        if previousURL.path != destination.path {
            try? fm.removeItem(at: previousURL)
        }
        UserDefaults.standard.set(directory.path, forKey: Self.directoryKey)
    }

    func resetToDefaultLocation() throws {
        try relocate(to: Self.defaultDirectory)
        UserDefaults.standard.removeObject(forKey: Self.directoryKey)
    }

    // MARK: Persistence

    /// One-time copy of the database from the app's previous name ("In Your Face").
    private func migrateLegacyDatabase() {
        let legacyFile = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InYourFace", isDirectory: true)
            .appendingPathComponent("database.json")
        if !FileManager.default.fileExists(atPath: fileURL.path),
           FileManager.default.fileExists(atPath: legacyFile.path) {
            try? FileManager.default.copyItem(at: legacyFile, to: fileURL)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(FileFormat.self, from: data) {
            events = file.events
            subscriptions = file.subscriptions
            hiddenIDs = Set(file.hiddenIDs ?? [])
        }
    }

    private func save() {
        events.sort { $0.start < $1.start }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = FileFormat(
            version: 1,
            events: events,
            subscriptions: subscriptions,
            hiddenIDs: hiddenIDs.isEmpty ? nil : Array(hiddenIDs).sorted()
        )
        if let data = try? encoder.encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Imports reminders saved by the pre-database version (UserDefaults).
    private func migrateLegacyReminders() {
        struct LegacyReminder: Codable {
            let id: UUID
            var title: String
            var fireDate: Date
        }
        let key = "customReminders"
        guard let data = UserDefaults.standard.data(forKey: key),
              let legacy = try? JSONDecoder().decode([LegacyReminder].self, from: data) else { return }
        for reminder in legacy where !events.contains(where: { $0.id == "manual-\(reminder.id.uuidString)" }) {
            events.append(StoredEvent(
                id: "manual-\(reminder.id.uuidString)",
                title: reminder.title,
                start: reminder.fireDate,
                end: reminder.fireDate.addingTimeInterval(30 * 60),
                isAllDay: false,
                source: .manual,
                calendarName: "Reminder",
                colorHex: "#FF9500",
                meetingLink: nil,
                notes: nil,
                subscriptionID: nil,
                dismissedAt: nil
            ))
        }
        UserDefaults.standard.removeObject(forKey: key)
        save()
    }

    // MARK: Manual reminders

    func addReminder(title: String, date: Date, link: String?, repeatRule: String? = nil) {
        events.append(StoredEvent(
            id: "manual-\(UUID().uuidString)",
            title: title,
            start: date,
            end: date.addingTimeInterval(30 * 60),
            isAllDay: false,
            source: .manual,
            calendarName: "Reminder",
            colorHex: "#FF9500",
            meetingLink: link,
            notes: nil,
            subscriptionID: nil,
            dismissedAt: nil,
            repeatRule: repeatRule
        ))
        save()
    }

    func updateReminder(id: String, title: String, date: Date, link: String?, repeatRule: String? = nil) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].title = title
        events[index].start = date
        events[index].end = date.addingTimeInterval(30 * 60)
        events[index].meetingLink = link
        events[index].repeatRule = repeatRule
        events[index].dismissedAt = nil
        save()
    }

    /// Marks a repeating reminder's current occurrence done and appends the
    /// next one, so past occurrences stay in the history.
    func completeAndScheduleNext(id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        let event = events[index]
        events[index].dismissedAt = Date()
        guard let rule = event.repeatRule,
              let nextStart = Self.nextOccurrence(after: Date(), from: event.start, rule: rule) else {
            save()
            return
        }
        let next = StoredEvent(
            id: "manual-\(UUID().uuidString)",
            title: event.title,
            start: nextStart,
            end: nextStart.addingTimeInterval(30 * 60),
            isAllDay: false,
            source: .manual,
            calendarName: event.calendarName,
            colorHex: event.colorHex,
            meetingLink: event.meetingLink,
            notes: event.notes,
            subscriptionID: nil,
            dismissedAt: nil,
            repeatRule: rule
        )
        events.append(next)
        save()
    }

    static func nextOccurrence(after date: Date, from start: Date, rule: String) -> Date? {
        let calendar = Calendar.current
        var candidate = start
        for _ in 0..<1000 {
            switch rule {
            case "daily":
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = next
            case "weekly":
                guard let next = calendar.date(byAdding: .day, value: 7, to: candidate) else { return nil }
                candidate = next
            case "weekdays":
                repeat {
                    guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                    candidate = next
                } while calendar.isDateInWeekend(candidate)
            default:
                return nil
            }
            if candidate > date { return candidate }
        }
        return nil
    }

    /// Removes an event from the app only. Synced events are remembered as
    /// hidden so the next sync doesn't bring them back; the real calendar
    /// event is untouched.
    func deleteEvent(id: String) {
        if let event = events.first(where: { $0.id == id }), event.source != .manual {
            hiddenIDs.insert(id)
        }
        events.removeAll { $0.id == id }
        save()
    }

    func markDismissed(id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].dismissedAt = Date()
        save()
    }

    // MARK: Sync

    /// Replaces all events of `source`/`subscriptionID` whose start falls inside `window`
    /// with the freshly fetched set. Events outside the window stay — that's the history.
    func replaceSynced(source: StoredEvent.Source, subscriptionID: UUID?, window: DateInterval, with fresh: [StoredEvent]) {
        events.removeAll { $0.source == source && $0.subscriptionID == subscriptionID && window.contains($0.start) }
        events.append(contentsOf: fresh.filter { window.contains($0.start) && !hiddenIDs.contains($0.id) })
        save()
    }

    func prune(olderThan interval: TimeInterval = 365 * 86400) {
        let cutoff = Date().addingTimeInterval(-interval)
        let before = events.count
        events.removeAll { $0.end < cutoff }
        if events.count != before { save() }
    }

    // MARK: Subscriptions

    private static let subscriptionPalette = ["#4285F4", "#0B8043", "#8E24AA", "#F4511E", "#039BE5", "#F6BF26"]

    @discardableResult
    func addSubscription(name: String, url: String) -> ICSSubscription {
        let color = Self.subscriptionPalette[subscriptions.count % Self.subscriptionPalette.count]
        let subscription = ICSSubscription(id: UUID(), name: name, url: url, colorHex: color, lastSync: nil)
        subscriptions.append(subscription)
        save()
        return subscription
    }

    func removeSubscription(id: UUID) {
        subscriptions.removeAll { $0.id == id }
        events.removeAll { $0.subscriptionID == id }
        save()
    }

    func touchSubscription(id: UUID) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index].lastSync = Date()
        save()
    }
}

// MARK: - Color helpers

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#3478F6" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }

    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Rotates the hue — used to derive the second stop of the accent gradient.
    func hueShifted(by delta: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: fmod(hue + delta + 1, 1),
            saturation: saturation,
            brightness: brightness,
            alpha: alpha
        )
    }
}
