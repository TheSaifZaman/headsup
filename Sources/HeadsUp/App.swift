import AppKit

@main
@MainActor
struct HeadsUpApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Regular app: visible in the Dock and Spotlight, launchable like any
        // other app — the menu bar status item is kept as the quick countdown.
        app.setActivationPolicy(.regular)
        app.run()
    }
}
