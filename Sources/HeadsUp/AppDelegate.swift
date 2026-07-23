import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let calendarManager = CalendarManager()
    private var scheduler: AlertScheduler!
    private var syncManager: SyncManager!
    private var scheduleWindow: NSWindow?
    private var syncTimer: Timer?
    private var tickTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        scheduler = AlertScheduler()
        syncManager = SyncManager(calendarManager: calendarManager)

        // The menu bar item is a countdown + one-click doorway into the app —
        // no dropdown, no second interface.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "eyes.inverse", accessibilityDescription: "Heads Up")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Heads Up — click to open"
        }

        applyAppearanceSettings()
        NotificationCenter.default.addObserver(forName: .appearanceSettingsChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in
                self.applyAppearanceSettings()
            }
        }

        Task {
            _ = await calendarManager.requestAccess()
            await syncManager.syncAll()
            updateStatusTitle()
        }

        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                await self.syncManager.syncAll()
                self.updateStatusTitle()
            }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                self.scheduler.tick()
                self.updateStatusTitle()
            }
        }

        // One-time: default Launch at Login to on — an alert app only protects
        // you while it's running. The Settings toggle can turn it off.
        if !UserDefaults.standard.bool(forKey: "didDefaultLoginItem") {
            UserDefaults.standard.set(true, forKey: "didDefaultLoginItem")
            try? SMAppService.mainApp.register()
        }

        openSchedule()

        // First launch: open the getting-started guide.
        if !UserDefaults.standard.bool(forKey: "didShowWelcomeGuide") {
            UserDefaults.standard.set(true, forKey: "didShowWelcomeGuide")
            openHelp()
        }
    }

    @objc private func openHelp() {
        openSchedule()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .helpRequested, object: nil)
        }
    }

    /// Dock icon click / Spotlight launch of an already-running instance.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSchedule()
        }
        return true
    }

    /// Closing every window keeps the app alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Applies the "Show Dock icon" / "Show menu bar countdown" settings.
    /// At least one stays on — otherwise the app would become unreachable.
    private func applyAppearanceSettings() {
        let settings = AppSettings.shared
        if !settings.showDockIcon && !settings.showMenuBarItem {
            settings.showMenuBarItem = true
            return  // the change re-posts the notification; we run again
        }
        statusItem.isVisible = settings.showMenuBarItem
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
    }

    /// Menu-bar-only apps have no main menu by default, which means the
    /// standard Edit key equivalents (⌘C/⌘V/⌘X/⌘A/⌘Z) never reach text
    /// fields. Installing an Edit menu wires them up.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Heads Up", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Heads Up", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(makeItem("Schedule…", #selector(openSchedule), key: "1"))
        fileMenu.addItem(makeItem("New Reminder…", #selector(newReminder), key: "n"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeItem("Sync Now", #selector(syncNow), key: "r"))
        fileMenu.addItem(makeItem("Test Alert…", #selector(testAlert), key: "t"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        helpMenu.addItem(makeItem("Heads Up Help", #selector(openHelp), key: "?"))
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Menu bar title

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        guard let next = scheduler.nextEvent else {
            button.title = ""
            return
        }
        let title = String(next.title.prefix(22))
        let until = next.start.timeIntervalSinceNow
        if until <= 0 {
            button.title = " Now: \(title)"
        } else if until < 3600 {
            button.title = " \(Int(until / 60))m • \(title)"
        } else {
            button.title = " \(next.start.formatted(date: .omitted, time: .shortened)) • \(title)"
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        openSchedule()
    }

    @objc private func testAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Test the full-screen alert"
        alert.informativeText = "Optionally paste a meeting link (Zoom, Meet, Teams…) to try the Join button. Leave empty to test without one."
        alert.addButton(withTitle: "Show Alert")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://meet.google.com/…  (optional)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var link = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty && !link.lowercased().hasPrefix("http") {
            link = "https://" + link
        }
        scheduler.showTestAlert(meetingLink: link.isEmpty ? nil : link)
    }

    @objc private func syncNow() {
        Task {
            await syncManager.syncAll()
            updateStatusTitle()
        }
    }

    @objc private func newReminder() {
        openSchedule()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .newReminderRequested, object: nil)
        }
    }

    @objc func openSchedule() {
        if scheduleWindow == nil {
            let view = ScheduleView(
                calendarManager: calendarManager,
                syncManager: syncManager,
                onTestAlert: { [weak self] in self?.testAlert() }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Heads Up"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 780, height: 620))
            window.isReleasedWhenClosed = false
            window.center()
            scheduleWindow = window
        }
        scheduleWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        openSchedule()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
        }
    }
}
