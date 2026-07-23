import SwiftUI

/// What the reminder form hands back on save.
struct ReminderDraft {
    var title: String
    var fireDate: Date
    var link: String?
    var repeatRule: String?
    var saveToAppleCalendar: Bool
}

/// Create or edit a manual reminder — including an optional Zoom/Meet/any
/// meeting link that the alert's Join button will open, and a repeat rule.
struct ReminderForm: View {
    var editing: StoredEvent?
    var allowCalendarSave = false
    var onCancel: (() -> Void)?
    let onSave: (ReminderDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var fireDate: Date
    @State private var link: String
    @State private var repeatRule: String
    @State private var saveToAppleCalendar = false

    private let presets: [(String, Int)] = [("5 min", 5), ("10 min", 10), ("30 min", 30), ("1 hour", 60)]
    private let repeatOptions: [(String, String)] = [
        ("Never", "none"), ("Daily", "daily"), ("Weekdays", "weekdays"), ("Weekly", "weekly"),
    ]

    init(
        editing: StoredEvent? = nil,
        allowCalendarSave: Bool = false,
        onCancel: (() -> Void)? = nil,
        onSave: @escaping (ReminderDraft) -> Void
    ) {
        self.editing = editing
        self.allowCalendarSave = allowCalendarSave
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: editing?.title ?? "")
        _fireDate = State(initialValue: editing?.start ?? Date().addingTimeInterval(10 * 60))
        _link = State(initialValue: editing?.meetingLink ?? "")
        _repeatRule = State(initialValue: editing?.repeatRule ?? "none")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "New Reminder" : "Edit Reminder")
                .font(.title2.bold())

            TextField("What do you need to do?", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                ForEach(presets, id: \.1) { label, minutes in
                    Button(label) {
                        fireDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
                    }
                }
            }

            DatePicker("Remind me at", selection: $fireDate)

            Picker("Repeat", selection: $repeatRule) {
                ForEach(repeatOptions, id: \.1) { label, value in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .disabled(saveToAppleCalendar)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Meeting link (optional) — Zoom, Meet, Teams…", text: $link)
                    .textFieldStyle(.roundedBorder)
                Text("The alert gets a Join button that opens this link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if editing == nil && allowCalendarSave {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Save to Apple Calendar instead of app-only", isOn: $saveToAppleCalendar)
                    Text("Creates a real calendar event (syncs to your phone). Repeat is app-only, so it's disabled with this on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel?()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Remind Me" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        var trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLink.isEmpty && !trimmedLink.lowercased().hasPrefix("http") {
            trimmedLink = "https://" + trimmedLink
        }
        onSave(ReminderDraft(
            title: trimmedTitle.isEmpty ? "Reminder" : trimmedTitle,
            fireDate: fireDate,
            link: trimmedLink.isEmpty ? nil : trimmedLink,
            repeatRule: repeatRule == "none" ? nil : repeatRule,
            saveToAppleCalendar: saveToAppleCalendar
        ))
    }
}
