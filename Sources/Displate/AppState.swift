import AppKit
import CoreGraphics
import ServiceManagement
import SwiftUI

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    var name: String
    var isBuiltIn: Bool
    var isMain: Bool
    var brightness: Double
    var brightnessMethod: BrightnessMethod
    var hasDDC: Bool
    var softwareDimmingForced: Bool
    var modes: [DisplayMode]
    var currentMode: DisplayMode?
    var hasHiDPIModes: Bool
    var hasOverride: Bool
    var contrast: Double?
    /// Sizes offered in the resolution grid: same HiDPI-ness and refresh rate as the current mode.
    var gridModes: [DisplayMode]
    /// Refresh rates available at the current size.
    var refreshRates: [Double]

    var subtitle: String {
        var parts: [String] = []
        if let mode = currentMode {
            parts.append(mode.sizeLabel)
            if mode.isHiDPI { parts.append("HiDPI") }
            if mode.refreshRate > 0 { parts.append("\(Int(mode.refreshRate.rounded())) Hz") }
        }
        return parts.joined(separator: " · ")
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private enum Keys {
        static let shortcuts = "shortcuts"
        static let showAllModes = "showAllModes"
        static let showHUD = "showHUD"
        static let brightnessStep = "brightnessStep"
        static let syncBrightness = "syncBrightness"
    }

    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var shortcuts: [HotkeyAction: Shortcut] = [:]

    @Published var showAllModes = UserDefaults.standard.bool(forKey: Keys.showAllModes) {
        didSet {
            UserDefaults.standard.set(showAllModes, forKey: Keys.showAllModes)
            refresh()
        }
    }

    @Published var showHUD = UserDefaults.standard.object(forKey: Keys.showHUD) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showHUD, forKey: Keys.showHUD) }
    }

    @Published var brightnessStep = UserDefaults.standard.object(forKey: Keys.brightnessStep) as? Double ?? 0.0625 {
        didSet { UserDefaults.standard.set(brightnessStep, forKey: Keys.brightnessStep) }
    }

    @Published var syncBrightness = UserDefaults.standard.bool(forKey: Keys.syncBrightness) {
        didSet { UserDefaults.standard.set(syncBrightness, forKey: Keys.syncBrightness) }
    }

    @Published var launchAtLogin = false {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Displate: launch at login failed: \(error)")
            }
        }
    }

    private var names: [CGDirectDisplayID: String] = [:]
    private var refreshTask: Task<Void, Never>?

    // MARK: Lifecycle

    func start() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loadShortcuts()
        HotkeyManager.shared.handler = { [weak self] action in self?.perform(action) }
        registerHotkeys()
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, nil)
        refresh()
    }

    func stop() {
        HotkeyManager.shared.unregisterAll()
        BrightnessController.shared.restoreAll()
    }

    func scheduleRefresh(after delay: Double = 0.4) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        for screen in NSScreen.screens {
            if let id = screen.displayID { names[id] = screen.localizedName }
        }
        let ids = DisplayModes.onlineDisplays()
        let brightness = BrightnessController.shared
        brightness.updateServices(for: ids, names: names)

        displays = ids.map { id in
            let all = DisplayModes.list(for: id)
            let current = DisplayModes.current(for: id)
            return DisplayInfo(
                id: id,
                name: name(for: id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                brightness: brightness.brightness(for: id),
                brightnessMethod: brightness.method(for: id),
                hasDDC: brightness.hasDDC(id),
                softwareDimmingForced: brightness.isSoftwareForced(id),
                modes: showAllModes ? all : DisplayModes.withoutLowResolutionDuplicates(all),
                currentMode: current,
                hasHiDPIModes: all.contains(where: \.isHiDPI),
                hasOverride: HiDPI.hasOverride(id),
                contrast: brightness.contrast(for: id),
                gridModes: Self.gridModes(all, current: current),
                refreshRates: Self.refreshRates(all, current: current)
            )
        }
        .sorted { ($0.isMain ? 0 : 1, $0.id) < ($1.isMain ? 0 : 1, $1.id) }
    }

    func brightnessDidChange(for display: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == display }) else { return }
        displays[index].brightness = BrightnessController.shared.brightness(for: display)
        displays[index].contrast = BrightnessController.shared.contrast(for: display)
    }

    private static func gridModes(_ modes: [DisplayMode], current: DisplayMode?) -> [DisplayMode] {
        guard let current else { return [] }
        var seen = Set<String>()
        return modes
            .filter { $0.isHiDPI == current.isHiDPI }
            .sorted { (abs($0.refreshRate - current.refreshRate), -$0.refreshRate) < (abs($1.refreshRate - current.refreshRate), -$1.refreshRate) }
            .filter { seen.insert($0.sizeLabel).inserted }
            .map { mode in
                // Prefer the exact current mode for the current size so the selection matches.
                (mode.width == current.width && mode.height == current.height) ? current : mode
            }
            .sorted { ($0.width * $0.height, $0.width) < ($1.width * $1.height, $1.width) }
    }

    private static func refreshRates(_ modes: [DisplayMode], current: DisplayMode?) -> [Double] {
        guard let current else { return [] }
        let rates = modes
            .filter { $0.width == current.width && $0.height == current.height && $0.isHiDPI == current.isHiDPI && $0.refreshRate > 0 }
            .map { $0.refreshRate.rounded() }
        return Array(Set(rates)).sorted()
    }

    private func name(for display: CGDirectDisplayID) -> String {
        names[display] ?? (CGDisplayIsBuiltin(display) != 0 ? "Built-in Display" : "Display \(display)")
    }

    // MARK: Display actions

    func setBrightness(_ value: Double, for display: CGDirectDisplayID, animated: Bool = false) {
        let value = min(max(value, 0), 1)
        let targets = syncBrightness ? displays.map(\.id) : [display]
        for target in targets {
            if animated {
                BrightnessController.shared.animateBrightness(to: value, for: target)
            } else {
                BrightnessController.shared.setBrightness(value, for: target)
            }
            if let index = displays.firstIndex(where: { $0.id == target }) {
                displays[index].brightness = value
            }
        }
    }

    func setContrast(_ value: Double, for display: CGDirectDisplayID) {
        BrightnessController.shared.setContrast(value, for: display)
        if let index = displays.firstIndex(where: { $0.id == display }) {
            displays[index].contrast = min(max(value, 0), 1)
        }
    }

    func setSoftwareDimming(_ forced: Bool, for display: CGDirectDisplayID) {
        BrightnessController.shared.setSoftwareForced(forced, for: display)
        refresh()
    }

    func applyMode(_ modeID: Int32, for display: CGDirectDisplayID) {
        guard let mode = DisplayModes.list(for: display).first(where: { $0.id == modeID }) else { return }
        // Update the UI first so the selection animates, then reconfigure (which blocks briefly).
        if let index = displays.firstIndex(where: { $0.id == display }) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                displays[index].currentMode = mode
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            DisplayModes.apply(mode, to: display)
            self.scheduleRefresh(after: 0.2)
        }
    }

    func setRefreshRate(_ rate: Double, for display: CGDirectDisplayID) {
        guard let current = DisplayModes.current(for: display),
              let mode = DisplayModes.list(for: display).first(where: {
                  $0.width == current.width && $0.height == current.height && $0.isHiDPI == current.isHiDPI && $0.refreshRate.rounded() == rate
              }) else { return }
        applyMode(mode.id, for: display)
    }

    func toggleHiDPI(for display: CGDirectDisplayID, showIndicator: Bool = false) {
        switch HiDPI.toggle(display) {
        case .switched(let mode):
            if showIndicator {
                HUD.shared.show(symbol: mode.isHiDPI ? "sparkles.tv" : "tv", title: mode.isHiDPI ? "HiDPI On" : "HiDPI Off", subtitle: mode.sizeLabel, on: display)
            }
        case .unavailable:
            if showIndicator {
                HUD.shared.show(symbol: "exclamationmark.triangle", title: "No HiDPI Modes", subtitle: "Unlock them from the menu", on: display)
            }
        }
        scheduleRefresh()
    }

    func installHiDPIOverride(for display: CGDirectDisplayID) {
        if let error = HiDPI.installOverride(for: display, name: name(for: display)) {
            showAlert("Could not unlock HiDPI modes", error)
        } else {
            showAlert("HiDPI modes unlocked",
                      "Disconnect and reconnect the monitor (or log out and back in). HiDPI resolutions will then appear in the list and the HiDPI toggle will work.")
        }
        refresh()
    }

    func removeHiDPIOverride(for display: CGDirectDisplayID) {
        if let error = HiDPI.removeOverride(for: display) {
            showAlert("Could not remove the override", error)
        }
        refresh()
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: Shortcuts

    func perform(_ action: HotkeyAction) {
        guard let display = displayUnderMouse() else { return }
        switch action {
        case .brightnessUp: adjustBrightness(by: brightnessStep, on: display)
        case .brightnessDown: adjustBrightness(by: -brightnessStep, on: display)
        case .resolutionNext: cycleResolution(1, on: display)
        case .resolutionPrevious: cycleResolution(-1, on: display)
        case .toggleHiDPI: toggleHiDPI(for: display, showIndicator: true)
        }
    }

    private func displayUnderMouse() -> CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
        return screen?.displayID
    }

    private func adjustBrightness(by delta: Double, on display: CGDirectDisplayID) {
        let current = BrightnessController.shared.targetBrightness(for: display)
        // Snap to the step grid so repeated presses land on even values.
        let steps = ((current + delta) / brightnessStep).rounded()
        let value = min(max(steps * brightnessStep, 0), 1)
        setBrightness(value, for: display, animated: true)
        let symbol = value < 0.01 ? "sun.min" : value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        HUD.shared.show(symbol: symbol, title: "\(Int((value * 100).rounded()))%",
                        subtitle: syncBrightness ? "All Displays" : name(for: display), value: value, on: display)
    }

    private func cycleResolution(_ direction: Int, on display: CGDirectDisplayID) {
        guard let current = DisplayModes.current(for: display) else { return }
        var seen = Set<String>()
        let candidates = DisplayModes.list(for: display)
            .filter { $0.isHiDPI == current.isHiDPI && abs($0.refreshRate - current.refreshRate) < 1 }
            .sorted { $0.width * $0.height < $1.width * $1.height }
            .filter { seen.insert($0.sizeLabel).inserted }

        guard let index = candidates.firstIndex(where: { $0.width == current.width && $0.height == current.height }) else { return }
        let next = index + direction
        guard candidates.indices.contains(next) else {
            HUD.shared.show(symbol: "rectangle.dashed", title: current.sizeLabel,
                            subtitle: direction > 0 ? "Largest resolution" : "Smallest resolution", on: display)
            return
        }
        let mode = candidates[next]
        var detail = mode.isHiDPI ? "HiDPI" : "Low resolution"
        if mode.refreshRate > 0 { detail += " · \(Int(mode.refreshRate.rounded())) Hz" }
        HUD.shared.show(symbol: direction > 0 ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                        title: mode.sizeLabel, subtitle: detail, on: display)
        // Let the indicator appear before the (briefly blocking) reconfiguration.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            DisplayModes.apply(mode, to: display)
            self.scheduleRefresh()
        }
    }

    func registerHotkeys() {
        HotkeyManager.shared.register(shortcuts)
    }

    func setShortcut(_ shortcut: Shortcut?, for action: HotkeyAction) {
        if let shortcut {
            for (other, existing) in shortcuts where other != action && existing.keyCode == shortcut.keyCode && existing.modifiers == shortcut.modifiers {
                shortcuts[other] = nil
            }
        }
        shortcuts[action] = shortcut
        saveShortcuts()
        registerHotkeys()
    }

    func resetShortcuts() {
        shortcuts = HotkeyAction.defaults
        saveShortcuts()
        registerHotkeys()
    }

    private func loadShortcuts() {
        guard let data = UserDefaults.standard.data(forKey: Keys.shortcuts),
              let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data) else {
            shortcuts = HotkeyAction.defaults
            return
        }
        var result: [HotkeyAction: Shortcut] = [:]
        for (key, value) in stored {
            if let action = HotkeyAction(rawValue: key) { result[action] = value }
        }
        shortcuts = result
    }

    private func saveShortcuts() {
        let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Keys.shortcuts)
        }
    }
}

private func displayReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ userInfo: UnsafeMutableRawPointer?) {
    guard !flags.contains(.beginConfigurationFlag) else { return }
    Task { @MainActor in AppState.shared.scheduleRefresh() }
}
