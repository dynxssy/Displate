import AppKit
import SwiftUI

@MainActor
final class PanelModel: ObservableObject {
    @Published var presented = false
}

/// Menu bar icon plus a custom rounded, vibrant panel (instead of MenuBarExtra's square window).
@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    static let margin: CGFloat = 20 // room for the SwiftUI shadow
    private var statusItem: NSStatusItem?
    private var panel: MenuPanel?
    private let model = PanelModel()
    private var panelTop: CGFloat = 0
    private var anchorX: CGFloat = 0
    private var screenFrame: NSRect = .zero
    private var contentSize: CGSize = .zero
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var closeTask: Task<Void, Never>?

    var isOpen: Bool { model.presented }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "Unload")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        statusItem = item

        let panel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300))
        let root = PanelRoot(model: model, state: AppModel.shared) { [weak self] size in
            self?.contentDidResize(size)
        }
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
    }

    /// Live memory reading next to the menu bar icon.
    func updateTitle() {
        guard let button = statusItem?.button else { return }
        let model = AppModel.shared
        let memory = model.memory
        let text: String
        switch model.menuBarStyle {
        case .percent: text = memory.total > 0 ? "\(Int((memory.usedFraction * 100).rounded()))%" : ""
        case .gigabytes: text = memory.total > 0 ? memory.used.memoryString : ""
        case .icon: text = ""
        }
        let color: NSColor = memory.pressure == .critical ? .systemRed : memory.pressure == .warning ? .systemOrange : .labelColor
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
            .baselineOffset: 0.5,
        ])
        button.toolTip = "Memory used: \(memory.used.memoryString) of \(memory.total.memoryString) · Pressure \(memory.pressure.label)"
    }

    @objc private func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard let panel, !model.presented else { return }
        closeTask?.cancel()
        AppModel.shared.panelDidOpen()
        computeAnchor()
        if contentSize == .zero {
            contentSize = panel.contentView?.fittingSize ?? CGSize(width: 360, height: 300)
        }
        layoutPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem?.button?.highlight(true)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { model.presented = true }
        installMonitors()
    }

    func close() {
        guard model.presented else { return }
        removeMonitors()
        AppModel.shared.panelDidClose()
        statusItem?.button?.highlight(false)
        withAnimation(.easeIn(duration: 0.15)) { model.presented = false }
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(170))
            guard let self, !Task.isCancelled, !self.model.presented else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func computeAnchor() {
        guard let button = statusItem?.button, let window = button.window else { return }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        screenFrame = screen?.visibleFrame ?? .zero
        anchorX = frame.midX
        panelTop = min(frame.minY, screenFrame.maxY) - 6 + Self.margin
    }

    private func contentDidResize(_ size: CGSize) {
        guard size != contentSize, size.width > 0, size.height > 0 else { return }
        contentSize = size
        if model.presented { layoutPanel() }
    }

    private func layoutPanel() {
        guard let panel else { return }
        let width = contentSize.width
        let height = contentSize.height
        var x = anchorX - width / 2
        if screenFrame.width > 0 {
            x = min(max(x, screenFrame.minX + 6 - Self.margin), screenFrame.maxX - 6 + Self.margin - width)
        }
        panel.setFrame(NSRect(x: x, y: panelTop - height, width: width, height: height), display: true)
    }

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.close()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}

final class MenuPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct SizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct PanelRoot: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var state: AppModel
    let onSize: (CGSize) -> Void

    var body: some View {
        MenuView(model: state)
            .background(VisualEffectBackground(material: .popover))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
            .scaleEffect(model.presented ? 1 : 0.94, anchor: .top)
            .offset(y: model.presented ? 0 : -8)
            .opacity(model.presented ? 1 : 0)
            .padding(StatusBarController.margin)
            .fixedSize()
            .background(GeometryReader { geometry in
                Color.clear.preference(key: SizeKey.self, value: geometry.size)
            })
            .onPreferenceChange(SizeKey.self) { size in onSize(size) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
