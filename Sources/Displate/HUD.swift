import AppKit
import SwiftUI

/// Small on-screen indicator shown when a shortcut is used.
@MainActor
final class HUD {
    static let shared = HUD()

    private static let size = NSSize(width: 220, height: 160)
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(symbol: String, title: String, value: Double? = nil, on display: CGDirectDisplayID? = nil) {
        guard AppState.shared.showHUD else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: HUDView(symbol: symbol, title: title, value: value))

        let screen = display.flatMap { id in NSScreen.screens.first { $0.displayID == id } } ?? NSScreen.main
        if let frame = screen?.frame {
            panel.setFrame(NSRect(x: frame.midX - Self.size.width / 2, y: frame.minY + frame.height * 0.16,
                                  width: Self.size.width, height: Self.size.height), display: true)
        }
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
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
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

private struct HUDView: View {
    let symbol: String
    let title: String
    let value: Double?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .medium))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let value {
                ProgressView(value: value)
                    .progressViewStyle(.linear)
                    .frame(width: 150)
            }
        }
        .padding(16)
        .frame(width: 220, height: 160)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
