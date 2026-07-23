import AppKit
import SwiftUI

/// The main window: frosted glass chrome, brand top bar, and four views of
/// your time — list, week, month, stats.
struct ScheduleView: View {
    let calendarManager: CalendarManager
    @ObservedObject var syncManager: SyncManager
    var onTestAlert: () -> Void = {}

    @ObservedObject private var db = Database.shared
    // Observed so accent/theme changes restyle the window live.
    @ObservedObject private var settings = AppSettings.shared
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
        ZStack {
            WindowBackdrop().ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.leading, 78)   // clears the traffic lights
                    .padding(.trailing, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                ZStack {
                    switch mode {
                    case .list: listView.transition(modeTransition)
                    case .week: weekView.transition(modeTransition)
                    case .month: monthView.transition(modeTransition)
                    case .stats: statsView.transition(modeTransition)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: mode)
            }
        }
        .frame(minWidth: 880, minHeight: 640)
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
                    Text("Settings").font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Button("Done") { showingSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                Divider()
                SettingsView(calendarManager: calendarManager, syncManager: syncManager)
            }
        }
        .sheet(isPresented: $showingHelp) {
            HelpView { showingHelp = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
            creating = false
            showingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newReminderRequested)) { _ in
            showingSettings = false
            creating = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .helpRequested)) { _ in
            creating = false
            showingSettings = false
            showingHelp = true
        }
    }

    private var modeTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        )
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

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Text("👀")
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .background(Brand.gradient, in: Circle())
                Text("Heads Up")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
            }

            SegmentedPill(
                options: ViewMode.allCases.map { ($0, $0.rawValue) },
                selection: $mode
            )

            Spacer()

            if let next = nextJoinable, let url = next.meetingURL {
                JoinNextButton(event: next, url: url)
            }

            IconActionButton(systemName: "plus", tooltip: "New reminder (⌘N)", prominent: true) {
                creating = true
            }
            IconActionButton(systemName: "arrow.triangle.2.circlepath", tooltip: "Sync calendars now", busy: syncManager.isSyncing) {
                Task { await syncManager.syncAll() }
            }
            IconActionButton(systemName: "bell.badge", tooltip: "Test the full-screen alert") {
                onTestAlert()
            }
            IconActionButton(systemName: "questionmark", tooltip: "How to use Heads Up") {
                showingHelp = true
            }
            IconActionButton(systemName: "gearshape.fill", tooltip: "Settings (⌘,)") {
                showingSettings = true
            }
        }
    }

    private var nextJoinable: StoredEvent? {
        let now = Date()
        return db.events
            .filter { $0.end > now && !$0.isAllDay && $0.meetingURL != nil }
            .filter { !($0.source == .manual && $0.dismissedAt != nil) }
            .min { $0.start < $1.start }
    }

    private var upNext: StoredEvent? {
        let now = Date()
        return db.events
            .filter { $0.end > now && !$0.isAllDay }
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
        VStack(spacing: 12) {
            if filter != .past, let next = upNext {
                UpNextHero(event: next)
            }

            HStack(spacing: 10) {
                SegmentedPill(
                    options: ListFilter.allCases.map { ($0, $0.rawValue) },
                    selection: $filter,
                    compact: true
                )
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Search events", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .frame(width: 170)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            }

            if groupedByDay.isEmpty {
                emptyState("Nothing here. Sync a calendar, add a reminder, or clear the search.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(groupedByDay, id: \.day) { group in
                            dayHeader(group.day)
                            ForEach(group.items) { event in
                                EventRow(
                                    event: event,
                                    onEdit: { editing = $0 },
                                    onDelete: { db.deleteEvent(id: $0.id) }
                                )
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func dayHeader(_ day: Date) -> some View {
        HStack {
            Text(sectionTitle(for: day))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func sectionTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInTomorrow(day) { return "TOMORROW" }
        if calendar.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(date: .complete, time: .omitted).uppercased()
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
            navHeader(
                title: weekTitle(days: days),
                onPrev: { shiftWeek(-1) },
                onNext: { shiftWeek(1) },
                onToday: { weekAnchor = Date() }
            )

            ScrollView {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        weekColumn(day: day, items: (groups[day] ?? []).sorted { $0.start < $1.start })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func weekTitle(days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private func navHeader(title: String, onPrev: @escaping () -> Void, onNext: @escaping () -> Void, onToday: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            IconActionButton(systemName: "chevron.left", tooltip: "Previous", action: onPrev)
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(minWidth: 200)
            IconActionButton(systemName: "chevron.right", tooltip: "Next", action: onNext)
            Spacer()
            Button("Today", action: onToday)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
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
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(isToday ? Color.white : Color.secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(isToday ? Color.white : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isToday ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.04)))
            )

            if items.isEmpty {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            } else {
                ForEach(items) { event in
                    WeekChip(event: event) {
                        if event.source == .manual {
                            editing = event
                        } else if let url = event.meetingURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Month view

    private var eventsByDay: [Date: [StoredEvent]] {
        Dictionary(grouping: db.events) { Calendar.current.startOfDay(for: $0.start) }
    }

    private var monthView: some View {
        // Group once per render — DayCell lookups must not re-group the whole DB.
        let groups = eventsByDay
        return VStack(spacing: 0) {
            navHeader(
                title: month.formatted(.dateTime.month(.wide).year()),
                onPrev: { shiftMonth(-1) },
                onNext: { shiftMonth(1) },
                onToday: {
                    month = Date()
                    selectedDay = Calendar.current.startOfDay(for: Date())
                }
            )

            weekdayHeader
            monthGrid(groups: groups)
            selectedDayList(groups: groups)
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            month = next
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
                Text(symbol.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(
                        day: day,
                        events: groups[day] ?? [],
                        isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDay),
                        isToday: Calendar.current.isDateInToday(day)
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedDay = day
                        }
                    }
                } else {
                    Color.clear.frame(minHeight: 54)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func selectedDayList(groups: [Date: [StoredEvent]]) -> some View {
        let items = (groups[selectedDay] ?? []).sorted { $0.start < $1.start }
        return VStack(alignment: .leading, spacing: 4) {
            Text(selectedDay.formatted(date: .complete, time: .omitted).uppercased())
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
            if items.isEmpty {
                emptyState("No events on this day")
                    .frame(maxHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(items) { event in
                            EventRow(
                                event: event,
                                onEdit: { editing = $0 },
                                onDelete: { db.deleteEvent(id: $0.id) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 210)
                // Fresh list per day — never carry rows over from another date.
                .id(selectedDay)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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
        let weeklyAverage = meetingStats(in: past8).hours / 8

        let dayHours: [(day: Date, hours: Double)] = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: thisWeek.start),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return (day, meetingStats(in: DateInterval(start: day, end: dayEnd)).hours)
        }

        let byWeekday = Dictionary(grouping: meetings.filter { past8.contains($0.start) }) {
            calendar.component(.weekday, from: $0.start)
        }
        let busiest = byWeekday
            .mapValues { $0.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 3600 } }
            .max { $0.value < $1.value }
        let busiestName = busiest.map { calendar.weekdaySymbols[$0.key - 1] } ?? "—"

        let recent = DateInterval(start: past8.start, end: thisWeek.end)
        let titleCounts = Dictionary(grouping: meetings.filter { recent.contains($0.start) }, by: \.title)
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
            .prefix(5)

        return AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        StatTile(value: "\(current.count)", unit: "meetings", caption: "this week", prominent: true)
                        StatTile(value: String(format: "%.1f h", current.hours), unit: "in meetings", caption: "this week")
                        StatTile(value: String(format: "%.1f h", previous.hours), unit: "last week", caption: "\(previous.count) meetings")
                        StatTile(value: String(format: "%.1f h", weeklyAverage), unit: "weekly avg", caption: "past 8 weeks")
                        StatTile(value: busiestName, unit: "busiest day", caption: "past 8 weeks")
                    }

                    WeekBars(dayHours: dayHours)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("MOST FREQUENT MEETINGS · PAST 8 WEEKS")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        if titleCounts.isEmpty {
                            Text("No meeting history yet.").foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(titleCounts), id: \.key) { title, count in
                                    HStack {
                                        Text(title).font(.system(size: 13)).lineLimit(1)
                                        Spacer()
                                        Text("\(count)×")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 7)
                                    if title != titleCounts.last?.key {
                                        Divider().opacity(0.5)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .card()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
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

// MARK: - Up-next hero

private struct UpNextHero: View {
    let event: StoredEvent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, event.start.timeIntervalSince(context.date))
            let started = event.start <= context.date

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(started ? "HAPPENING NOW" : "UP NEXT")
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .opacity(0.85)
                    Text(event.title)
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                    Text("\(event.calendarName) · \(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.85)
                }

                Spacer()

                if !started {
                    Text(heroCountdown(remaining))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                }

                if let url = event.meetingURL {
                    HeroJoinButton(url: url)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Brand.primary.opacity(0.3), radius: 16, y: 6)
        }
    }

    private func heroCountdown(_ remaining: TimeInterval) -> String {
        let total = Int(remaining)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct HeroJoinButton: View {
    let url: URL
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label("Join", systemImage: "video.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .help(url.absoluteString)
    }
}

private struct JoinNextButton: View {
    let event: StoredEvent
    let url: URL
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label("Join Next", systemImage: "video.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Brand.gradient, in: Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.05 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .help("Join \(event.title) (\(event.start.formatted(date: .omitted, time: .shortened)))")
    }
}

// MARK: - Week chip

private struct WeekChip: View {
    let event: StoredEvent
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: event.color))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(event.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: event.color).opacity(hovering ? 0.22 : 0.11),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .opacity(event.end < Date() ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
        .help(event.title)
    }
}

// MARK: - Stat tile & bars

private struct StatTile: View {
    let value: String
    let unit: String
    let caption: String
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .opacity(prominent ? 0.9 : 1)
            Text(caption)
                .font(.system(size: 10.5))
                .foregroundStyle(prominent ? Color.white.opacity(0.8) : Color.secondary)
        }
        .foregroundStyle(prominent ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background {
            if prominent {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.gradient)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.thinMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(prominent ? 0 : 0.07), lineWidth: 1)
        )
    }
}

private struct WeekBars: View {
    let dayHours: [(day: Date, hours: Double)]
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THIS WEEK · HOURS PER DAY")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            let maxHours = max(dayHours.map(\.hours).max() ?? 0, 0.01)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(dayHours, id: \.day) { entry in
                    VStack(spacing: 5) {
                        Text(entry.hours > 0 ? String(format: "%.1f", entry.hours) : "")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Brand.gradient)
                            .frame(height: appeared ? max(5, CGFloat(entry.hours / maxHours) * 110) : 5)
                        Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: Calendar.current.isDateInToday(entry.day) ? .bold : .regular))
                            .foregroundStyle(Calendar.current.isDateInToday(entry.day) ? Brand.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150, alignment: .bottom)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .card()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: Date
    let events: [StoredEvent]
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday || isSelected ? .bold : .regular, design: .rounded))
                    .foregroundStyle(isToday ? Brand.primary : Color.primary)
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
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.09) : (hovering ? Color.primary.opacity(0.05) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.clear), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Event row

struct EventRow: View {
    let event: StoredEvent
    var onEdit: ((StoredEvent) -> Void)?
    var onDelete: ((StoredEvent) -> Void)?

    @State private var confirmingDelete = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.color))
                .frame(width: 4, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    if event.isAllDay { badge("all-day") }
                    badge(sourceLabel)
                    if let repeatLabel = event.repeatLabel { badge("↻ \(repeatLabel)") }
                    if event.source == .manual && event.dismissedAt != nil { badge("done") }
                }
                Text(timeString)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 2) {
                if let url = event.meetingURL {
                    IconActionButton(systemName: "video.fill", tooltip: "Join: \(url.absoluteString)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                if event.source == .manual {
                    IconActionButton(systemName: "pencil", tooltip: "Edit reminder") {
                        onEdit?(event)
                    }
                }
                IconActionButton(
                    systemName: "trash",
                    tooltip: event.source == .manual ? "Delete reminder" : "Remove from this app (stays in your calendar)"
                ) {
                    if event.source == .manual {
                        onDelete?(event)
                    } else {
                        confirmingDelete = true
                    }
                }
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
            .opacity(hovering ? 1 : 0.25)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .opacity(event.end < Date() ? 0.6 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
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
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
