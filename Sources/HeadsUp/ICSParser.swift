import Foundation

struct ParsedICSEvent {
    var uid: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var urlString: String?
}

/// Pragmatic iCalendar parser: enough for Google Calendar / Outlook ICS feeds.
/// Handles line unfolding, timezones, all-day events, and common RRULE
/// recurrences (DAILY / WEEKLY with BYDAY / MONTHLY / YEARLY, INTERVAL,
/// COUNT, UNTIL, EXDATE). Exotic recurrence rules are approximated or skipped.
enum ICSParser {

    static func parse(_ text: String, window: DateInterval) -> [ParsedICSEvent] {
        let lines = unfold(text)
        var events: [ParsedICSEvent] = []
        var inEvent = false
        var props: [(name: String, params: [String: String], value: String)] = []

        for line in lines {
            if line == "BEGIN:VEVENT" {
                inEvent = true
                props = []
            } else if line == "END:VEVENT" {
                if inEvent {
                    events.append(contentsOf: makeEvents(props: props, window: window))
                }
                inEvent = false
            } else if inEvent, let property = parseProperty(line) {
                props.append(property)
            }
        }
        return events
    }

    // MARK: Line handling

    /// ICS wraps long lines; a continuation line starts with a space or tab.
    private static func unfold(_ text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !result.isEmpty {
                result[result.count - 1] += String(line.dropFirst())
            } else {
                result.append(line)
            }
        }
        return result
    }

    /// NAME(;PARAM=VALUE)*:VALUE — the first unquoted colon separates head from value.
    private static func parseProperty(_ line: String) -> (name: String, params: [String: String], value: String)? {
        var inQuotes = false
        var colonIndex: String.Index?
        for index in line.indices {
            let char = line[index]
            if char == "\"" {
                inQuotes.toggle()
            } else if char == ":" && !inQuotes {
                colonIndex = index
                break
            }
        }
        guard let colon = colonIndex else { return nil }
        let head = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])

        let parts = head.split(separator: ";").map(String.init)
        guard let name = parts.first?.uppercased(), !name.isEmpty else { return nil }
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 {
                params[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return (name, params, value)
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: Dates

    /// Returns (date, isAllDay).
    static func parseDate(_ value: String, params: [String: String]) -> (Date, Bool)? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if params["VALUE"] == "DATE" || (value.count == 8 && !value.contains("T")) {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = .current
            guard let date = formatter.date(from: value) else { return nil }
            return (date, true)
        }

        if value.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
        } else {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            formatter.timeZone = params["TZID"].flatMap(TimeZone.init(identifier:)) ?? .current
        }
        guard let date = formatter.date(from: value) else { return nil }
        return (date, false)
    }

    // MARK: Event assembly

    private static func makeEvents(
        props: [(name: String, params: [String: String], value: String)],
        window: DateInterval
    ) -> [ParsedICSEvent] {
        var dtStart: (Date, Bool)?
        var dtEnd: (Date, Bool)?
        var summary = "Untitled"
        var uid = UUID().uuidString
        var location: String?
        var notes: String?
        var urlString: String?
        var rrule: String?
        var exdates = Set<Int>()
        var cancelled = false

        for (name, params, value) in props {
            switch name {
            case "DTSTART": dtStart = parseDate(value, params: params)
            case "DTEND": dtEnd = parseDate(value, params: params)
            case "SUMMARY": summary = unescape(value)
            case "DESCRIPTION": notes = unescape(value)
            case "LOCATION": location = unescape(value)
            case "URL": urlString = value
            case "UID": uid = value
            case "RRULE": rrule = value
            case "STATUS": cancelled = (value.uppercased() == "CANCELLED")
            case "EXDATE":
                for piece in value.split(separator: ",") {
                    if let (date, _) = parseDate(String(piece), params: params) {
                        exdates.insert(Int(date.timeIntervalSince1970))
                    }
                }
            default:
                break
            }
        }

        guard !cancelled, let (start, isAllDay) = dtStart else { return [] }
        let end = dtEnd?.0 ?? (isAllDay ? start.addingTimeInterval(86400) : start.addingTimeInterval(3600))
        let duration = max(end.timeIntervalSince(start), 60)

        let starts: [Date]
        if let rrule {
            starts = expand(rrule: rrule, dtStart: start, window: window, exdates: exdates)
        } else {
            starts = (start >= window.start && start <= window.end) ? [start] : []
        }

        return starts.map { occurrenceStart in
            ParsedICSEvent(
                uid: uid,
                title: summary,
                start: occurrenceStart,
                end: occurrenceStart.addingTimeInterval(duration),
                isAllDay: isAllDay,
                location: location,
                notes: notes,
                urlString: urlString
            )
        }
    }

    // MARK: Recurrence expansion

    private static func expand(rrule: String, dtStart: Date, window: DateInterval, exdates: Set<Int>) -> [Date] {
        var freq = ""
        var interval = 1
        var count: Int?
        var until: Date?
        var byDays: [Int] = []  // Calendar weekday numbers: 1=Sun … 7=Sat

        for part in rrule.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            switch pair[0].uppercased() {
            case "FREQ": freq = pair[1].uppercased()
            case "INTERVAL": interval = max(1, Int(pair[1]) ?? 1)
            case "COUNT": count = Int(pair[1])
            case "UNTIL": until = parseDate(pair[1], params: [:])?.0
            case "BYDAY":
                let map = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
                byDays = pair[1].split(separator: ",").compactMap { map[String($0.suffix(2))] }
            default:
                break
            }
        }

        let calendar = Calendar.current
        var result: [Date] = []
        var emitted = 0

        func admit(_ date: Date) -> Bool {
            if let until, date > until { return false }
            if let count, emitted >= count { return false }
            emitted += 1
            if date >= window.start, date <= window.end, !exdates.contains(Int(date.timeIntervalSince1970)) {
                result.append(date)
            }
            return true
        }

        var iterations = 0
        let maxIterations = 20000

        switch freq {
        case "DAILY":
            var date = dtStart
            while iterations < maxIterations, date <= window.end {
                if !admit(date) { break }
                guard let next = calendar.date(byAdding: .day, value: interval, to: date) else { break }
                date = next
                iterations += 1
            }

        case "WEEKLY":
            if byDays.isEmpty {
                var date = dtStart
                while iterations < maxIterations, date <= window.end {
                    if !admit(date) { break }
                    guard let next = calendar.date(byAdding: .day, value: 7 * interval, to: date) else { break }
                    date = next
                    iterations += 1
                }
            } else {
                // Walk day by day from DTSTART; emit days whose weekday matches
                // BYDAY and whose week index respects INTERVAL.
                let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: dtStart)?.start ?? dtStart
                var date = dtStart
                var stop = false
                while iterations < maxIterations, date <= window.end, !stop {
                    let weekday = calendar.component(.weekday, from: date)
                    if byDays.contains(weekday) {
                        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
                        let days = calendar.dateComponents([.day], from: anchorWeek, to: currentWeek).day ?? 0
                        if (days / 7) % interval == 0 {
                            if !admit(date) { stop = true }
                        }
                    }
                    guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                    date = next
                    iterations += 1
                }
            }

        case "MONTHLY":
            var date = dtStart
            while iterations < maxIterations, date <= window.end {
                if !admit(date) { break }
                guard let next = calendar.date(byAdding: .month, value: interval, to: date) else { break }
                date = next
                iterations += 1
            }

        case "YEARLY":
            var date = dtStart
            while iterations < maxIterations, date <= window.end {
                if !admit(date) { break }
                guard let next = calendar.date(byAdding: .year, value: interval, to: date) else { break }
                date = next
                iterations += 1
            }

        default:
            // Unknown FREQ — fall back to the first occurrence only.
            _ = admit(dtStart)
        }

        return result
    }
}
