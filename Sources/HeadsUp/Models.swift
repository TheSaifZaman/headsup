import AppKit
import SwiftUI

// MARK: - Alert themes

enum Theme: String, CaseIterable, Identifiable {
    case classic = "Classic Red"
    case sunset = "Sunset"
    case ocean = "Ocean"
    case forest = "Forest"
    case midnight = "Midnight"

    var id: String { rawValue }

    var gradient: [Color] {
        switch self {
        case .classic:
            return [Color(red: 0.78, green: 0.07, blue: 0.11), Color(red: 0.42, green: 0.0, blue: 0.22)]
        case .sunset:
            return [Color(red: 0.95, green: 0.45, blue: 0.13), Color(red: 0.72, green: 0.11, blue: 0.42)]
        case .ocean:
            return [Color(red: 0.05, green: 0.35, blue: 0.65), Color(red: 0.02, green: 0.12, blue: 0.30)]
        case .forest:
            return [Color(red: 0.09, green: 0.45, blue: 0.27), Color(red: 0.02, green: 0.18, blue: 0.12)]
        case .midnight:
            return [Color(red: 0.16, green: 0.17, blue: 0.30), Color(red: 0.04, green: 0.04, blue: 0.10)]
        }
    }
}

// MARK: - Settings

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var leadTimeMinutes: Int {
        didSet { defaults.set(leadTimeMinutes, forKey: "leadTimeMinutes") }
    }
    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: "playSound") }
    }
    @Published var themeName: String {
        didSet { defaults.set(themeName, forKey: "themeName") }
    }
    @Published var disabledCalendarIDs: Set<String> {
        didSet { defaults.set(Array(disabledCalendarIDs), forKey: "disabledCalendarIDs") }
    }
    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: "showDockIcon")
            NotificationCenter.default.post(name: .appearanceSettingsChanged, object: nil)
        }
    }
    @Published var showMenuBarItem: Bool {
        didSet {
            defaults.set(showMenuBarItem, forKey: "showMenuBarItem")
            NotificationCenter.default.post(name: .appearanceSettingsChanged, object: nil)
        }
    }
    /// Repeat the alert sound every 30s until the alert is dismissed.
    @Published var repeatAlertSound: Bool {
        didSet { defaults.set(repeatAlertSound, forKey: "repeatAlertSound") }
    }
    /// Skip meetings the user has declined.
    @Published var ignoreDeclinedEvents: Bool {
        didSet { defaults.set(ignoreDeclinedEvents, forKey: "ignoreDeclinedEvents") }
    }
    /// Minutes before an event to show the small floating countdown pill (0 = off).
    @Published var preAlertMinutes: Int {
        didSet { defaults.set(preAlertMinutes, forKey: "preAlertMinutes") }
    }
    /// Automatically open the meeting link at start time.
    @Published var autoJoinMeetings: Bool {
        didSet { defaults.set(autoJoinMeetings, forKey: "autoJoinMeetings") }
    }

    var theme: Theme { Theme(rawValue: themeName) ?? .classic }

    /// One-time copy of settings saved under the app's previous bundle id.
    private static func migrateLegacyDefaults(into defaults: UserDefaults) {
        guard defaults.object(forKey: "leadTimeMinutes") == nil,
              let legacy = UserDefaults(suiteName: "local.inyourface.clone") else { return }
        let keys = [
            "leadTimeMinutes", "playSound", "themeName", "disabledCalendarIDs",
            "showDockIcon", "showMenuBarItem", "repeatAlertSound",
            "ignoreDeclinedEvents", "preAlertMinutes", "autoJoinMeetings",
        ]
        for key in keys {
            if let value = legacy.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }

    private init() {
        Self.migrateLegacyDefaults(into: defaults)
        leadTimeMinutes = defaults.object(forKey: "leadTimeMinutes") as? Int ?? 2
        playSound = defaults.object(forKey: "playSound") as? Bool ?? true
        themeName = defaults.string(forKey: "themeName") ?? Theme.classic.rawValue
        disabledCalendarIDs = Set(defaults.stringArray(forKey: "disabledCalendarIDs") ?? [])
        showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? true
        showMenuBarItem = defaults.object(forKey: "showMenuBarItem") as? Bool ?? true
        repeatAlertSound = defaults.object(forKey: "repeatAlertSound") as? Bool ?? false
        ignoreDeclinedEvents = defaults.object(forKey: "ignoreDeclinedEvents") as? Bool ?? true
        preAlertMinutes = defaults.object(forKey: "preAlertMinutes") as? Int ?? 10
        autoJoinMeetings = defaults.object(forKey: "autoJoinMeetings") as? Bool ?? false
    }
}

extension Notification.Name {
    static let appearanceSettingsChanged = Notification.Name("appearanceSettingsChanged")
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
    static let newReminderRequested = Notification.Name("newReminderRequested")
    static let helpRequested = Notification.Name("helpRequested")
}
