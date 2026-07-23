import AppKit
import SwiftUI

/// Browse everything in the database — past, current, and future meetings and
/// reminders — as a grouped list, week agenda, month calendar, or stats.
struct ScheduleView: View {
    let calendarManager: CalendarManager
    @ObservedObject var syncManager: SyncManager
    var onTestAlert: () -> Void = {}

    @ObservedObject private var db = Database.shared
    @State private var showingSettings = false
    @State private var showingHelp = false

    @State private var mode: ViewMode = .list
    @State private var filter: ListFilter = .upcoming
    @State private var searchText = ""
    @State private var month = Date()
    @State private var weekAnchor = Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var editing: StoredEvent?
    @State private var creating = false

    enum ViewMode: String, CaseIterable { case list = "List", week = "Week", month = "Month", stats = "Stats" }
    enum ListFilter: String, CaseIterable { case past = "Past", upcoming = "Upcoming", all = "All" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch mode {
            case .list: listView
            case .week: weekView
            case .month: monthView
            case .stats: statsView
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .sheet(item: $editing) { event in
            ReminderForm(editing: event) { draft in
                db.updateReminder(id: event.id, title: draft.title, date: draft.fireDate, link: draft.link, repeatRule: draft.repeatRule)
                editing = nil
            }
        }
        .sheet(isPresented: $creating) {
            ReminderForm(allowCalendarSave: calendarManager.hasAccess) { draft in
                handleCreate(draft)
            }
        }
        .sheet(isPresented: $showingSettings) {
            VStack(spacing: 0) {
                HStack {
                    Text("Settings").font(.headline)
                    Spacer()
                    Button("Done") { showingSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                Divider()
                SettingsView(calendarManager: calendarManager, syncManager: syncManager)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
            creating = false
            showingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newReminderRequested)) { _ in
            showingSettings = false
            creating = true
        }
        .sheet(isPresented: $showingHelp) {
            HelpView { showingHelp = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .helpRequested)) { _ in
            creating = false
            showingSettings = false
            showingHelp = true
        }
    }

    private func handleCreate(_ draft: ReminderDraft) {
        if draft.saveToAppleCalendar {
            calendarManager.createEvent(title: draft.title, start: draft.fireDate, urlString: draft.link)
            Task { await syncManager.syncAll() }
        } else {
            db.addReminder(title: draft.title, date: draft.fireDate, link: draft.link, repeatRule: draft.repeatRule)
        }
        creating = false
    }

    private var header: some View {
        HStack {
            Picker("", selection: $mode) {
                ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            if mode == .list {
                Picker("", selection: $filter) {
                    ForEach(ListFilter.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }

            Spacer()

            if let next = nextJoinable, let url = next.meetingURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Join Next", systemImage: "video.fill")
                }
                .help("Join \(next.title) (\(next.start.formatted(date: .omitted, time: .shortened)))")
            }

            Button {
                creating = true
            } label: {
                Label("New Reminder", systemImage: "plus")
            }

            Button {
                Task { await syncManager.syncAll() }
            } label: {
                if syncManager.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(syncManager.isSyncing)
            .help("Sync calendars now")

            Button {
                onTestAlert()
            } label: {
                Image(systemName: "bell.badge")
            }
            .help("Test the full-screen alert")

            Button {
                showingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("How to use Heads Up")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(12)
    }

    private var nextJoinable: StoredEvent? {
        let now = Date()
        return db.events
            .filter { $0.end > now && !$0.isAllDay && $0.meetingURL != nil }
            .filter { !($0.source == .manual && $0.dismissedAt != nil) }
            .min { $0.start < $1.start }
    }

    // MARK: - List view

    private var filteredEvents: [StoredEvent] {
        let now = Date()
        var events: [StoredEvent]
        switch filter {
        case .past: events = db.events.filter { $0.end <= now }
        case .upcoming: events = db.events.filter { $0.end > now }
        case .all: events = db.events
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            events = events.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.calendarName.localizedCaseInsensitiveContains(query)
            }
        }
        return events
    }

    private var groupedByDay: [(day: Date, items: [StoredEvent])] {
        let groups = Dictionary(grouping: filteredEvents) { Calendar.current.startOfDay(for: $0.start) }
        let keys = filter == .past ? groups.keys.sorted(by: >) : groups.keys.sorted()
        return keys.map { (day: $0, items: groups[$0]!.sorted { $0.start < $1.start }) }
    }

    private var listView: some View {
        Group {
            if groupedByDay.isEmpty {
                emptyState("Nothing here. Sync a calendar, add a reminder, or clear the search.")
            } else {
                List {
                    ForEach(groupedByDay, id: \.day) { group in
                        Section(sectionTitle(for: group.day)) {
                            ForEach(group.items) { event in
                                EventRow(
                                    event: event,
                                    onEdit: { editing = $0 },
                                    onDelete: { db.deleteEvent(id: $0.id) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func sectionTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today — \(day.formatted(date: .abbreviated, time: .omitted))" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow — \(day.formatted(date: .abbreviated, time: .omitted))" }
        if calendar.isDateInYesterday(day) { return "Yesterday — \(day.formatted(date: .abbreviated, time: .omitted))" }
        return day.formatted(date: .complete, time: .omitted)
    }

    // MARK: - Week view

    private var weekDays: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: weekAnchor) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var weekView: some View {
        let groups = eventsByDay
        let days = weekDays
        return VStack(spacing: 0) {
            HStack {
                Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                if let first = days.first, let last = days.last {
                    Text("\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.title3.bold())
                        .frame(width: 240)
                }
                Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                Spacer()
                Button("Today") { weekAnchor = Date() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ScrollView {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(days, id: \.self) { day in
                        weekColumn(day: day, items: (groups[day] ?? []).sorted { $0.start < $1.start })
                    }
                }
                .padding(10)
            }
        }
    }

    private func shiftWeek(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: 7 * delta, to: weekAnchor) {
            weekAnchor = next
        }
    }

    private func weekColumn(day: Date, items: [StoredEvent]) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        return VStack(spacing: 6) {
            VStack(spacing: 1) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.bold())
                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isToday ? Color.accentColor.opacity(0.12) : Color.clear)
            )

            if items.isEmpty {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            } else {
                ForEach(items) { event in
                    weekChip(event)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func weekChip(_ event: StoredEvent) -> some View {
        Button {
            if event.source == .manual { editing = event }
            else if let url = event.meetingURL { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: event.color))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(event.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: event.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .opacity(event.end < Date() ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .help(event.title)
    }

    // MARK: - Month view

    private var eventsByDay: [Date: [StoredEvent]] {
        Dictionary(grouping: db.events) { Calendar.current.startOfDay(for: $0.start) }
    }

    private var monthView: some View {
        // Group once per render — DayCell lookups must not re-group the whole DB.
        let groups = eventsByDay
        return VStack(spacing: 0) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.bold())
                    .frame(width: 180)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                Spacer()
                Button("Today") {
                    month = Date()
                    selectedDay = Calendar.current.startOfDay(for: Date())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            weekdayHeader
            monthGrid(groups: groups)
            Divider()
            selectedDayList(groups: groups)
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            month = next
            // Keep the selection inside the displayed month.
            let calendar = Calendar.current
            if !calendar.isDate(selectedDay, equalTo: next, toGranularity: .month),
               let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: next)) {
                selectedDay = calendar.isDate(Date(), equalTo: next, toGranularity: .month)
                    ? calendar.startOfDay(for: Date())
                    : firstOfMonth
            }
        }
    }

    private var weekdayHeader: some View {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        return HStack(spacing: 0) {
            ForEach(ordered, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private var monthDays: [Date?] {
        let calendar = Calendar.current
        guard let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = dayRange.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: firstOfMonth) }
        return Array(repeating: nil, count: leading) + days.map { Optional($0) }
    }

    private func monthGrid(groups: [Date: [StoredEvent]]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(
                        day: day,
                        events: groups[day] ?? [],
                        isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDay),
                        isToday: Calendar.current.isDateInToday(day)
                    ) {
                        selectedDay = day
                    }
                } else {
                    Color.clear.frame(minHeight: 52)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func selectedDayList(groups: [Date: [StoredEvent]]) -> some View {
        let items = (groups[selectedDay] ?? []).sorted { $0.start < $1.start }
        return VStack(alignment: .leading, spacing: 0) {
            Text(selectedDay.formatted(date: .complete, time: .omitted))
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            if items.isEmpty {
                emptyState("No events on this day")
                    .frame(maxHeight: 140)
            } else {
                List(items) { event in
                    EventRow(
                        event: event,
                        onEdit: { editing = $0 },
                        onDelete: { db.deleteEvent(id: $0.id) }
                    )
                }
                .listStyle(.inset)
                .frame(maxHeight: 220)
                // Force a fresh list per day — never carry rows over from the
                // previously selected date.
                .id(selectedDay)
            }
        }
    }

    // MARK: - Stats

    private var meetings: [StoredEvent] {
        db.events.filter { $0.source != .manual && !$0.isAllDay }
    }

    private func meetingStats(in interval: DateInterval) -> (count: Int, hours: Double) {
        let items = meetings.filter { interval.contains($0.start) }
        let hours = items.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 3600 }
        return (items.count, hours)
    }

    private var statsView: some View {
        let calendar = Calendar.current
        let now = Date()
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeek.start),
              let eightWeeksAgo = calendar.date(byAdding: .day, value: -56, to: thisWeek.start) else {
            return AnyView(emptyState("Not enough data yet"))
        }
        let lastWeek = DateInterval(start: lastWeekStart, end: thisWeek.start)
        let past8 = DateInterval(start: eightWeeksAgo, end: thisWeek.start)

        let current = meetingStats(in: thisWeek)
        let previous = meetingStats(in: lastWeek)
        let past8Stats = meetingStats(in: past8)
        let weeklyAverage = past8Stats.hours / 8

        // Hours per day of the current week.
        let dayHours: [(day: Date, hours: Double)] = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: thisWeek.start),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return (day, meetingStats(in: DateInterval(start: day, end: dayEnd)).hours)
        }
        let maxDayHours = max(dayHours.map(\.hours).max() ?? 0, 0.01)

        // Busiest weekday over the past 8 weeks.
        let byWeekday = Dictionary(grouping: meetings.filter { past8.contains($0.start) }) {
            calendar.component(.weekday, from: $0.start)
        }
        let busiest = byWeekday
            .mapValues { $0.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 3600 } }
            .max { $0.value < $1.value }
        let busiestName = busiest.map { calendar.weekdaySymbols[$0.key - 1] } ?? "—"

        // Most frequent meeting titles over the past 8 weeks + this week.
        let recent = DateInterval(start: past8.start, end: thisWeek.end)
        let titleCounts = Dictionary(grouping: meetings.filter { recent.contains($0.start) }, by: \.title)
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
            .prefix(5)

        return AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        StatTile(value: "\(current.count)", unit: "meetings", caption: "this week")
                        StatTile(value: String(format: "%.1f h", current.hours), unit: "in meetings", caption: "this week")
                        StatTile(value: String(format: "%.1f h", previous.hours), unit: "last week", caption: "\(previous.count) meetings")
                        StatTile(value: String(format: "%.1f h", weeklyAverage), unit: "weekly avg", caption: "past 8 weeks")
                        StatTile(value: busiestName, unit: "busiest day", caption: "past 8 weeks")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("This week, hours per day").font(.headline)
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(dayHours, id: \.day) { entry in
                                VStack(spacing: 4) {
                                    Text(entry.hours > 0 ? String(format: "%.1f", entry.hours) : "")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.accentColor.opacity(0.75))
                                        .frame(height: max(4, CGFloat(entry.hours / maxDayHours) * 110))
                                    Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                                        .font(.caption2)
                                        .foregroundStyle(Calendar.current.isDateInToday(entry.day) ? Color.accentColor : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 150)
                        .padding(.horizontal, 8)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Most frequent meetings (past 8 weeks)").font(.headline)
                        if titleCounts.isEmpty {
                            Text("No meeting history yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(titleCounts), id: \.key) { title, count in
                                HStack {
                                    Text(title).lineLimit(1)
                                    Spacer()
                                    Text("\(count)×").foregroundStyle(.secondary).monospacedDigit()
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding(20)
            }
        )
    }

    private func emptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let value: String
    let unit: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(unit).font(.caption.bold())
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: Date
    let events: [StoredEvent]
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                HStack(spacing: 3) {
                    ForEach(events.prefix(3), id: \.id) { event in
                        Circle()
                            .fill(Color(nsColor: event.color))
                            .frame(width: 5, height: 5)
                    }
                    if events.count > 3 {
                        Text("+\(events.count - 3)")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event row

struct EventRow: View {
    let event: StoredEvent
    var onEdit: ((StoredEvent) -> Void)?
    var onDelete: ((StoredEvent) -> Void)?
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.color))
                .frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title).fontWeight(.medium)
                    if event.isAllDay { badge("all-day") }
                    badge(sourceLabel)
                    if let repeatLabel = event.repeatLabel { badge("↻ \(repeatLabel)") }
                    if event.source == .manual && event.dismissedAt != nil { badge("done") }
                }
                Text(timeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let url = event.meetingURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "video.fill")
                }
                .buttonStyle(.borderless)
                .help("Join: \(url.absoluteString)")
            }
            if event.source == .manual {
                Button { onEdit?(event) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("Edit reminder")
            }
            Button {
                if event.source == .manual {
                    onDelete?(event)
                } else {
                    confirmingDelete = true
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(event.source == .manual ? "Delete reminder" : "Remove from this app (stays in your calendar)")
            .confirmationDialog(
                "Remove \"\(event.title)\" from Heads Up?",
                isPresented: $confirmingDelete
            ) {
                Button("Remove from app", role: .destructive) { onDelete?(event) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It stays in your calendar and won't come back on sync.")
            }
        }
        .padding(.vertical, 2)
        .opacity(event.end < Date() ? 0.55 : 1)
    }

    private var sourceLabel: String {
        switch event.source {
        case .manual: return "reminder"
        case .apple, .ics: return event.calendarName
        }
    }

    private var timeString: String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
