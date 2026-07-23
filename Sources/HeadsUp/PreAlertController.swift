import AppKit
import SwiftUI

/// Stage one of the two-stage alert: a small floating countdown pill in the
/// top-right corner. Non-activating, so it never steals focus. Stage two is
/// the full-screen takeover.
@MainActor
final class PreAlertController {
    private var panel: NSPanel?
    private(set) var showingEventID: String?

    func show(event: StoredEvent, onDismiss: @escaping () -> Void) {
        if showingEventID == event.id { return }
        dismiss()

        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 340, height: 74)
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - size.width - 16,
            y: screen.visibleFrame.maxY - size.height - 16
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let view = PreAlertView(event: event) { [weak self] in
            self?.dismiss()
            onDismiss()
        }
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()

        self.panel = panel
        showingEventID = event.id
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        showingEventID = nil
    }
}

private struct PreAlertView: View {
    let event: StoredEvent
    let onDismiss: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: event.color))
                    .frame(width: 4, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(countdown(now: context.date))
                        .font(.system(size: 12))
                        .monospacedDigit()
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
                    .help("Join now")
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Hide until the full alert")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func countdown(now: Date) -> String {
        let remaining = max(0, Int(event.start.timeIntervalSince(now)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "starts in %d:%02d · %@", minutes, seconds, event.start.formatted(date: .omitted, time: .shortened))
    }
}
