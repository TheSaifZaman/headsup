import AppKit
import SwiftUI

// MARK: - Brand

enum Brand {
    /// "Deadline heat" — the one accent in the app. #FF4D3D → #FF8A00.
    static let heatA = Color(red: 1.00, green: 0.30, blue: 0.24)
    static let heatB = Color(red: 1.00, green: 0.54, blue: 0.00)

    static var gradient: LinearGradient {
        LinearGradient(colors: [heatA, heatB], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Frosted window backdrop

/// Behind-window vibrancy — the frosted glass base the whole app sits on.
struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Cards

extension View {
    func card(cornerRadius: CGFloat = 14) -> some View {
        self
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

// MARK: - Round icon button

struct IconActionButton: View {
    let systemName: String
    let tooltip: String
    var busy = false
    var prominent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if prominent {
                    Circle().fill(Brand.gradient)
                } else {
                    Circle().fill(Color.primary.opacity(hovering ? 0.13 : 0.06))
                }
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(prominent ? .white : (hovering ? Color.primary : Color.secondary))
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .help(tooltip)
    }
}

// MARK: - Sliding-pill segmented control

struct SegmentedPill<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var compact = false

    @Namespace private var pillSpace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option in
                segment(option)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func segment(_ option: (T, String)) -> some View {
        let selected = option.0 == selection
        return Text(option.1)
            .font(.system(size: compact ? 11.5 : 12.5, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.vertical, compact ? 4.5 : 6)
            .background {
                if selected {
                    Capsule()
                        .fill(Brand.gradient)
                        .matchedGeometryEffect(id: "selection", in: pillSpace)
                }
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    selection = option.0
                }
            }
    }
}

// MARK: - Slow-drifting gradient (alert backdrop)

struct AnimatedGradientBackdrop: View {
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .scaleEffect(1.6)
            .rotationEffect(.degrees(drift ? 5 : -5))
            .hueRotation(.degrees(drift ? 9 : -9))
            .ignoresSafeArea()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                    drift = true
                }
            }
    }
}
