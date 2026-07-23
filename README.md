# Heads Up

A native macOS app that makes meetings impossible to miss — built for people with ADHD,
time blindness, or deep hyperfocus. Instead of a small notification you can
ignore, it takes over **every screen** with a full-screen alert before each
meeting.

## Features

- **Full-screen alerts** on all displays (breaks through full-screen apps) with
  a live countdown, snooze (1/5 min), dismiss, and a **Join** button
- **Menu bar countdown** to your next event (`14m • Standup`), with a dropdown
  of upcoming events
- **Self-contained local database** — everything lives in a human-readable
  JSON text file at `~/Library/Application Support/HeadsUp/database.json`
- **Apple Calendar sync** via EventKit (Google/Microsoft accounts added in
  System Settings → Internet Accounts flow through), with per-calendar filtering
- **Google Calendar / web sync without OAuth** — paste any ICS feed URL
  (Google's "Secret address in iCal format", Outlook, iCloud public calendars);
  the app fetches it every 5 minutes and saves events into the local DB.
  Includes recurring-event (RRULE) expansion
- **Custom reminders** with an **optional manual meeting link** (Zoom, Meet,
  Teams, anything) — the alert's Join button opens it
- **Schedule window** — list view of past / upcoming / all events grouped by
  day, plus a month calendar view; edit or delete reminders from there
- **One-click join** — meeting links auto-detected in event URLs, locations,
  and notes (Zoom, Google Meet, Teams, Webex, Whereby)
- **5 alert themes**, configurable lead time and alert sound

## Build & run

Requires macOS 14+ and the Swift toolchain (Xcode or Command Line Tools).

```sh
./build.sh install   # builds + copies to /Applications (Dock, Spotlight, Launchpad)
# or just ./build.sh to build without installing
```

The app is a regular Dock app (launch it from Spotlight like any other) and
*also* keeps a menu bar countdown. Closing its windows leaves it running in
the background; clicking the Dock icon reopens the Schedule window.

`build.sh` also produces the shareable artifacts:

- `dist/HeadsUp-2.0.dmg` — **send this to other people.** It contains the
  app, an Applications shortcut, and a "How to Install.txt" (the app is ad-hoc
  signed, so first launch needs right-click → Open).
- `dist/HeadsUp-2.0.zip` — same app, zip form.

With only Command Line Tools the binary is built for your Mac's architecture
(Apple Silicon). If full Xcode is installed, the script automatically builds a
universal binary that also runs on Intel Macs.

## Connecting Google Calendar

1. Open Google Calendar on the web → Settings → pick your calendar
2. Copy the URL under **"Secret address in iCal format"**
3. In the app: menu bar icon → Settings… → *Google / Web Calendars (ICS)* →
   paste it → **Add & Sync**

Read-only sync, no Google account credentials involved. Alternatively, add
your Google account in System Settings → Internet Accounts with Calendars
enabled and it arrives through Apple Calendar sync.

## Project layout

- `Sources/HeadsUp/App.swift` — entry point (menu-bar-only app)
- `Sources/HeadsUp/AppDelegate.swift` — status item, menu, timers, windows
- `Sources/HeadsUp/Database.swift` — the JSON text database (events,
  reminders, subscriptions) and color helpers
- `Sources/HeadsUp/SyncManager.swift` — pulls Apple Calendar + ICS feeds
  into the database (30 days back / 90 days ahead; older events are kept as
  history for up to a year)
- `Sources/HeadsUp/ICSParser.swift` — pragmatic iCalendar parser with
  RRULE recurrence expansion
- `Sources/HeadsUp/CalendarManager.swift` — EventKit access
- `Sources/HeadsUp/AlertScheduler.swift` — decides when alerts fire;
  snooze/dismiss state
- `Sources/HeadsUp/AlertController.swift` — the full-screen alert windows
  and SwiftUI alert view
- `Sources/HeadsUp/MeetingLinks.swift` — video-call link detection
- `Sources/HeadsUp/ScheduleView.swift` — list + month calendar window
- `Sources/HeadsUp/SettingsView.swift`, `ReminderView.swift` — SwiftUI forms
- `build.sh` — builds and packages `.app`, `.dmg`, `.zip`
