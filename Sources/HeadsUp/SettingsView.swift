import EventKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let calendarManager: CalendarManager
    @ObservedObject var syncManager: SyncManager
    @ObservedObject private var db = Database.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var calendars: [EKCalendar] = []
    @State private var newSubscriptionName = ""
    @State private var newSubscriptionURL = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var databaseError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text("The app only protects you while it's running — keep this on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Alerts") {
                Stepper(value: $settings.leadTimeMinutes, in: 0...30) {
                    Text("Full-screen alert \(settings.leadTimeMinutes) min before meetings")
                }
                Stepper(value: $settings.preAlertMinutes, in: 0...60) {
                    Text(settings.preAlertMinutes == 0
                         ? "Early countdown pill: off"
                         : "Early countdown pill \(settings.preAlertMinutes) min before")
                }
                Toggle("Play sound with alert", isOn: $settings.playSound)
                Toggle("Repeat sound every 30s until dismissed", isOn: $settings.repeatAlertSound)
                    .disabled(!settings.playSound)
                Toggle("Auto-join meetings at start time", isOn: $settings.autoJoinMeetings)
                Toggle("Ignore meetings I've declined", isOn: $settings.ignoreDeclinedEvents)
                Picker("Theme", selection: $settings.themeName) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
            }

            Section("Alert Backdrop") {
                Picker("Background", selection: $settings.alertBackgroundType) {
                    Text("Theme gradient").tag("theme")
                    Text("Custom image").tag("image")
                    Text("Custom video").tag("video")
                }
                .pickerStyle(.segmented)

                if settings.alertBackgroundType != "theme" {
                    HStack {
                        Text(backdropFileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(settings.alertBackgroundType == "image" ? "Choose Image…" : "Choose Video…") {
                            chooseBackdropFile()
                        }
                        if settings.alertBackgroundPath != nil {
                            Button("Clear") {
                                settings.alertBackgroundPath = nil
                            }
                        }
                    }
                    Text("Your image or looping video fills the whole alert screen (a dark overlay keeps the countdown readable). Falls back to the theme gradient if the file goes missing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                Toggle("Show menu bar countdown", isOn: $settings.showMenuBarItem)
                Text("At least one stays on so the app remains reachable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Accent", selection: $settings.accentMode) {
                    Text("Custom color").tag("custom")
                    Text("Match alert theme").tag("theme")
                }
                if settings.accentMode == "custom" {
                    ColorPicker("Accent color", selection: accentBinding, supportsOpacity: false)
                }
                HStack(spacing: 8) {
                    Text("Preview")
                    Capsule()
                        .fill(LinearGradient(colors: settings.accentColors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: 90, height: 16)
                    Spacer()
                    Button("Reset") {
                        settings.accentMode = "custom"
                        settings.accentColorHex = "#FF4D3D"
                    }
                }
                Text("The accent colors the Up Next card, mode switcher, join buttons, and today markers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Calendars") {
                if calendars.isEmpty {
                    Text("No calendars available. Grant calendar access in System Settings → Privacy & Security → Calendars. Google/Microsoft accounts added in System Settings → Internet Accounts show up here too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: binding(for: calendar)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(nsColor: calendar.color))
                                    .frame(width: 10, height: 10)
                                Text(calendar.title)
                            }
                        }
                    }
                }
            }

            Section("Google / Web Calendars (ICS)") {
                ForEach(db.subscriptions) { subscription in
                    HStack {
                        Circle()
                            .fill(Color(nsColor: NSColor(hex: subscription.colorHex)))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(subscription.name)
                            Text(lastSyncText(subscription))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            db.removeSubscription(id: subscription.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this subscription and its events")
                    }
                }

                TextField("Name (e.g. Work Google Calendar)", text: $newSubscriptionName)
                TextField("Secret iCal URL (https://…/basic.ics or webcal://…)", text: $newSubscriptionURL)
                HStack {
                    Button("Open Google Calendar Settings") {
                        NSWorkspace.shared.open(URL(string: "https://calendar.google.com/calendar/u/0/r/settings")!)
                    }
                    Spacer()
                    Button("Add & Sync") {
                        addSubscription()
                    }
                    .disabled(newSubscriptionURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Google Calendar → Settings → pick your calendar → \"Secret address in iCal format\" → copy the URL and paste it here. Any .ics feed works (Outlook, iCloud public calendars…). Read-only sync, refreshed every 5 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sync") {
                HStack {
                    Button(syncManager.isSyncing ? "Syncing…" : "Sync Now") {
                        Task { await syncManager.syncAll() }
                    }
                    .disabled(syncManager.isSyncing)
                    Spacer()
                    if let error = syncManager.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }

            Section("Database") {
                Text(db.fileURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button("Change Location…") { chooseDatabaseFolder() }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([db.fileURL])
                    }
                    Spacer()
                    Button("Reset to Default") {
                        do { try db.resetToDefaultLocation() } catch { databaseError = error.localizedDescription }
                    }
                    .disabled(db.isAtDefaultLocation)
                }
                Text("Tip: pick an iCloud Drive or Dropbox folder to carry your reminders across Macs. If the folder is ever unreachable, the app falls back to the default location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        .onAppear { calendars = calendarManager.calendars() }
        .alert("Couldn't move database", isPresented: showingDatabaseError) {
            Button("OK") { databaseError = nil }
        } message: {
            Text(databaseError ?? "")
        }
    }

    private var showingDatabaseError: Binding<Bool> {
        Binding(
            get: { databaseError != nil },
            set: { if !$0 { databaseError = nil } }
        )
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: settings.accentColorHex)) },
            set: { settings.accentColorHex = NSColor($0).hexString }
        )
    }

    private var backdropFileName: String {
        guard let path = settings.alertBackgroundPath else { return "No file chosen" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func chooseBackdropFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = settings.alertBackgroundType == "image" ? [.image] : [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Use This File"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.alertBackgroundPath = url.path
    }

    private func chooseDatabaseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose a folder for the Heads Up database (database.json will be moved there)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try db.relocate(to: url)
        } catch {
            databaseError = error.localizedDescription
        }
    }

    private func lastSyncText(_ subscription: ICSSubscription) -> String {
        guard let lastSync = subscription.lastSync else { return "Never synced" }
        return "Synced \(lastSync.formatted(date: .abbreviated, time: .shortened))"
    }

    private func addSubscription() {
        let url = newSubscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = newSubscriptionName.trimmingCharacters(in: .whitespaces)
        let subscription = db.addSubscription(name: name.isEmpty ? "Web Calendar" : name, url: url)
        newSubscriptionName = ""
        newSubscriptionURL = ""
        Task { await syncManager.sync(subscription) }
    }

    private func binding(for calendar: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledCalendarIDs.contains(calendar.calendarIdentifier) },
            set: { enabled in
                if enabled {
                    settings.disabledCalendarIDs.remove(calendar.calendarIdentifier)
                } else {
                    settings.disabledCalendarIDs.insert(calendar.calendarIdentifier)
                }
                Task { await syncManager.syncAll() }
            }
        )
    }
}
