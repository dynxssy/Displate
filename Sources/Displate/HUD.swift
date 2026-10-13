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

/// On-screen indicator shown when a shortcut is used, styled after the system volume/brightness HUD.
@MainActor
final class HUD {
    static let shared = HUD()

    private static let panelSize = NSSize(width: 260, height: 260)
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
        if let frame = screen?.frame, movedScreen || !model.visible {
            let size = Self.panelSize
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.12,
                                  width: size.width, height: size.height), display: false)
        }

        let wasVisible = model.visible && !movedScreen
        withAnimation(wasVisible ? Animation.smooth(duration: 0.18) : nil) {
            model.symbol = symbol
            model.title = title
            model.subtitle = subtitle
            model.value = value
        }
        panel.orderFrontRegardless()
        if !model.visible {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { model.visible = true }
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.22)) { self.model.visible = false }
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, !self.model.visible else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = hosting
        return panel
    }
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: model.symbol)
                .font(.system(size: 58, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .frame(height: 76)
                .padding(.top, 26)

            Spacer(minLength: 8)

            VStack(spacing: 3) {
                Text(model.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 14)

            Spacer(minLength: 8)

            if let value = model.value {
                SegmentedLevel(value: value)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            } else {
                Color.clear.frame(height: 30)
            }
        }
        .frame(width: 200, height: 200)
        .background(
            VisualEffectBackground(material: .hudWindow)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .scaleEffect(model.visible ? 1 : 0.86)
        .opacity(model.visible ? 1 : 0)
        .frame(width: 260, height: 260)
    }
}

/// 16 segment level indicator, like the system brightness HUD.
private struct SegmentedLevel: View {
    let value: Double
    private let segments = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                let fill = min(max(value * Double(segments) - Double(index), 0), 1)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.15))
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary.opacity(0.9))
                            .frame(width: geometry.size.width * fill)
                    }
                }
            }
        }
        .frame(height: 7)
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
