import AppKit
import SwiftUI

/// Getting-started guide. Shows automatically on first launch, and any time
/// via the ? button or Help menu.
struct HelpView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("👀 Welcome to Heads Up")
                    .font(.title2.bold())
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Heads Up makes meetings impossible to miss: it takes over your whole screen before each one. Built for ADHD, time blindness, and deep hyperfocus.")
                        .foregroundStyle(.secondary)

                    step("checkmark.circle", "1. Grant calendar access",
                         "Click Allow when macOS asks. Google and Microsoft accounts added in System Settings → Internet Accounts (with Calendars enabled) show up automatically. Pick which calendars count in Settings → Apple Calendars.")

                    step("link", "2. Connect Google Calendar directly (optional)",
                         "No Google sign-in needed. In Google Calendar on the web: Settings → pick your calendar → copy the \"Secret address in iCal format\" URL. Then here: Settings → Google / Web Calendars → paste → Add & Sync. Any .ics feed works (Outlook, iCloud public links). Syncs every 5 minutes.")

                    step("bell.badge", "3. How alerts work",
                         "Two stages: a small countdown pill appears in the corner (default 10 minutes before), then the full-screen takeover (default 2 minutes before — both adjustable in Settings). Snooze for 1/5 minutes or until 1 minute before start, join the call with one click, or dismiss with Esc. Optional: repeat the sound until dismissed, and auto-join meetings at start time.")

                    step("plus.circle", "4. Reminders for anything",
                         "⌘N creates a reminder for any time-critical task — with an optional Zoom/Meet/Teams link for the Join button, and Daily / Weekdays / Weekly repeats. Or save it straight into Apple Calendar so your phone gets it too.")

                    step("calendar", "5. Your schedule, four ways",
                         "List (with search and past history), Week agenda, Month calendar, and Stats — how many hours you spend in meetings, your busiest day, and your most frequent meetings. Deleting an event here only removes it from this app, never from your real calendar.")

                    step("gearshape", "6. Make it yours",
                         "Settings covers: launch at login (on by default), Dock icon and/or menu bar countdown, alert themes, and where the database file lives — point it at iCloud Drive or Dropbox to carry your data across Macs. Everything is stored in one human-readable database.json.")

                    step("shippingbox", "7. Share it",
                         "Anyone with a Mac (Apple Silicon, macOS 14+) can install with Homebrew:\n\nbrew tap TheSaifZaman/tap\nbrew install --cask heads-up --no-quarantine")

                    Text("Reopen this guide anytime: the ？ button up top, or Help → Heads Up Help.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    HStack(spacing: 6) {
                        Text("Made by MD Saif Zaman —")
                        Link("linkedin.com/in/thesaifzaman", destination: URL(string: "https://www.linkedin.com/in/thesaifzaman/")!)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 620)
    }

    private func step(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}
