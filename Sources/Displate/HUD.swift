import AppKit
import SwiftUI

@MainActor
final class HUDModel: ObservableObject {
    @Published var symbol = "sun.max.fill"
    @Published var title = ""
    @Published var subtitle: String?
    @Published var value: Double?
    @Published var visible = false
}

/// Compact indicator that drops down just below the menu bar (top right, like the macOS Tahoe OSD)
/// whenever a shortcut or brightness key is used.
@MainActor
final class HUD {
    static let shared = HUD()

    private static let size = NSSize(width: 340, height: 110) // includes room for the shadow
    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var currentScreen: CGDirectDisplayID?

    func show(symbol: String, title: String, subtitle: String? = nil, value: Double? = nil, on display: CGDirectDisplayID? = nil) {
        guard AppState.shared.showHUD else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let screen = display.flatMap { id in NSScreen.screens.first { $0.displayID == id } } ?? NSScreen.main
        let movedScreen = screen?.displayID != currentScreen
        currentScreen = screen?.displayID
        if let screen, movedScreen || !model.visible {
            let visible = screen.visibleFrame
            let size = Self.size
            panel.setFrame(NSRect(x: visible.maxX - size.width + 4, y: visible.maxY - size.height + 10,
                                  width: size.width, height: size.height), display: false)
        }

        let animateContent = model.visible && !movedScreen
        withAnimation(animateContent ? Animation.smooth(duration: 0.18) : nil) {
            model.symbol = symbol
            model.title = title
            model.subtitle = subtitle
            model.value = value
        }
        panel.orderFrontRegardless()
        if !model.visible {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { model.visible = true }
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.model.visible = false }
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled, !self.model.visible else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .vibrantDark)
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    var solidBackground = false // ImageRenderer cannot draw NSVisualEffectView

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.14))
                Image(systemName: model.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: model.value == nil ? 1 : 6) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let value = model.value {
                    LevelBar(value: value)
                } else if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let value = model.value {
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 300, height: 58)
        .background {
            if solidBackground {
                Color(white: 0.16)
            } else {
                VisualEffectBackground(material: .hudWindow)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .environment(\.colorScheme, .dark)
        .scaleEffect(model.visible ? 1 : 0.9, anchor: .top)
        .offset(y: model.visible ? 0 : -24)
        .opacity(model.visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 14)
    }
}

private struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(6, geometry.size.width * value))
            }
        }
        .frame(height: 6)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
