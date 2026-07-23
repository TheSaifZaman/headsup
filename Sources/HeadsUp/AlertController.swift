import AppKit
import SwiftUI

enum AlertAction {
    case dismissed
    case snoozed(minutes: Int)
    case snoozedUntilOneMinuteBefore
    case joined
}

/// Shows the full-screen, can't-miss-it alert on every connected display.
@MainActor
final class AlertController {
    private var windows: [NSWindow] = []
    private var soundTimer: Timer?
    private(set) var currentEventID: String?

    var isShowing: Bool { !windows.isEmpty }

    func show(event: StoredEvent, followUp: StoredEvent?, onAction: @escaping (AlertAction) -> Void) {
        guard !isShowing else { return }
        currentEventID = event.id

        if AppSettings.shared.playSound {
            NSSound(named: "Sosumi")?.play()
            if AppSettings.shared.repeatAlertSound {
                soundTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                    NSSound(named: "Sosumi")?.play()
                }
            }
        }

        for screen in NSScreen.screens {
            let window = KeyableWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = true
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false

            let view = AlertView(event: event, followUp: followUp) { [weak self] action in
                if case .joined = action, let url = event.meetingURL {
                    NSWorkspace.shared.open(url)
                }
                self?.dismiss()
                onAction(action)
            }
            window.contentView = NSHostingView(rootView: view)
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        soundTimer?.invalidate()
        soundTimer = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        currentEventID = nil
    }
}

/// Borderless windows refuse key status by default; we need it for keyboard shortcuts.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// MARK: - Full-screen alert view

struct AlertView: View {
    let event: StoredEvent
    var followUp: StoredEvent?
    let onAction: (AlertAction) -> Void

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            backdrop
            scrim

            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(now: context.date)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.94)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: Backdrop (theme gradient, custom image, or looping video)

    @ViewBuilder
    private var backdrop: some View {
        switch settings.alertBackdrop {
        case .image(let url):
            GeometryReader { geo in
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    AnimatedGradientBackdrop(colors: settings.theme.gradient)
                }
            }
            .ignoresSafeArea()
        case .video(let url):
            VideoBackground(url: url)
                .ignoresSafeArea()
        case .theme:
            AnimatedGradientBackdrop(colors: settings.theme.gradient)
        }
    }

    /// Keeps text readable over any backdrop.
    private var scrim: some View {
        LinearGradient(
            colors: [.black.opacity(0.55), .black.opacity(0.30), .black.opacity(0.60)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        let remaining = event.start.timeIntervalSince(now)
        let seconds = Int(abs(remaining))
        let pulsing = !reduceMotion && remaining > 0 && remaining <= 15

        VStack(spacing: 26) {
            Spacer()

            Text(headline(remaining: remaining))
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .tracking(7)
                .foregroundStyle(.white.opacity(0.75))

            Text(event.title)
                .font(.system(size: 62, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 60)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 4)

            VStack(spacing: 8) {
                Text(countdown(remaining: remaining))
                    .font(.system(size: 108, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 22, y: 6)
                    .scaleEffect(pulsing && seconds % 2 == 0 ? 1.045 : 1)
                    .animation(.easeInOut(duration: 0.45), value: seconds)
                Text(remaining >= 0 ? "until it starts" : "since it started")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(Color(nsColor: event.color))
                    .frame(width: 10, height: 10)
                Text(event.calendarName)
                Text("·")
                Text(event.start.formatted(date: .omitted, time: .shortened))
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(.white.opacity(0.14), in: Capsule())

            if let followUp {
                Text("Up next: \(followUp.title) at \(followUp.start.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            HStack(spacing: 14) {
                if event.meetingURL != nil {
                    AlertButton(title: "Join Meeting", prominent: true) {
                        onAction(.joined)
                    }
                }
                AlertButton(title: "Snooze 1 min") { onAction(.snoozed(minutes: 1)) }
                AlertButton(title: "Snooze 5 min") { onAction(.snoozed(minutes: 5)) }
                if remaining > 150 {
                    AlertButton(title: "Until 1 min before") { onAction(.snoozedUntilOneMinuteBefore) }
                }
                AlertButton(title: "Dismiss — I'm on it") { onAction(.dismissed) }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 70)
        }
    }

    private func headline(remaining: TimeInterval) -> String {
        if event.source == .manual { return "REMINDER" }
        return remaining >= 0 ? "MEETING STARTING" : "HAPPENING NOW"
    }

    private func countdown(remaining: TimeInterval) -> String {
        let total = Int(abs(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct AlertButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                .foregroundStyle(prominent ? .black : .white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(
                    prominent
                        ? AnyShapeStyle(.white)
                        : AnyShapeStyle(.white.opacity(hovering ? 0.26 : 0.15)),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0 : 0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.05 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }
}
