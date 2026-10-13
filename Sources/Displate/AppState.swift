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
    /// Up to five curated sizes, from "Larger Text" to "More Space" (like System Settings).
    var presets: [DisplayMode]
    var defaultModeID: Int32?
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
        static let useBrightnessKeys = "useBrightnessKeys"
        static let welcomeDismissed = "welcomeDismissed"
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

    @Published var useBrightnessKeys = UserDefaults.standard.object(forKey: Keys.useBrightnessKeys) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(useBrightnessKeys, forKey: Keys.useBrightnessKeys)
            MediaKeys.shared.update()
            if useBrightnessKeys { watchAccessibility() }
        }
    }

    @Published private(set) var accessibilityGranted = MediaKeys.isTrusted
    @Published private(set) var showWelcome = !UserDefaults.standard.bool(forKey: Keys.welcomeDismissed)

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
    private var accessibilityTask: Task<Void, Never>?
    /// Mode switches requested by shortcuts but not applied yet, so fast repeated presses keep stepping.
    private var pendingModes: [CGDirectDisplayID: DisplayMode] = [:]

    // MARK: Lifecycle

    func start() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loadShortcuts()
        HotkeyManager.shared.handler = { [weak self] action in self?.perform(action) }
        registerHotkeys()
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, nil)
        refresh()
        if useBrightnessKeys { watchAccessibility() }
    }

    func dismissWelcome() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showWelcome = false }
        UserDefaults.standard.set(true, forKey: Keys.welcomeDismissed)
    }

    func requestAccessibility() {
        MediaKeys.requestPermission()
        watchAccessibility()
    }

    /// Polls until Accessibility access is granted, then starts the brightness key tap.
    private func watchAccessibility() {
        accessibilityGranted = MediaKeys.isTrusted
        guard !accessibilityGranted, accessibilityTask == nil else {
            MediaKeys.shared.update()
            return
        }
        accessibilityTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self else { return }
                if MediaKeys.isTrusted {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { self.accessibilityGranted = true }
                    MediaKeys.shared.update()
                    self.accessibilityTask = nil
                    return
                }
            }
        }
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
            let presets = Self.presets(all, current: current)
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
                presets: presets.modes,
                defaultModeID: presets.defaultID,
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

    private static let niceWidths: Set<Int> = [1024, 1152, 1280, 1344, 1366, 1440, 1470, 1512, 1600, 1680, 1710, 1728,
                                                1800, 1920, 2048, 2056, 2240, 2304, 2560, 2880, 3008, 3200, 3360, 3440, 3840, 4096, 5120]

    /// Curated resolutions for the current HiDPI setting and refresh rate: up to five sizes around
    /// macOS' default, preferring familiar resolutions, always including the current one.
    static func presets(_ modes: [DisplayMode], current: DisplayMode?) -> (modes: [DisplayMode], defaultID: Int32?) {
        guard let current else { return ([], nil) }
        var seen = Set<String>()
        let sizes = modes
            .filter { $0.isHiDPI == current.isHiDPI }
            .sorted { (abs($0.refreshRate - current.refreshRate), $0.isDefault ? 0 : 1) < (abs($1.refreshRate - current.refreshRate), $1.isDefault ? 0 : 1) }
            .filter { seen.insert($0.sizeLabel).inserted }
            .map { ($0.width == current.width && $0.height == current.height) ? current : $0 }
            .sorted { $0.width < $1.width }
        guard !sizes.isEmpty else { return ([current], current.id) }

        let defaultMode = Self.defaultMode(sizes, all: modes, current: current)
        guard sizes.count > 5 else { return (sizes, defaultMode.id) }

        let minWidth = Double(sizes.first!.width)
        let maxWidth = Double(sizes.last!.width)
        func pick(_ target: Double) -> DisplayMode {
            let target = min(max(target, minWidth), maxWidth)
            let near = sizes.filter { abs(Double($0.width) - target) <= target * 0.08 }
            let nice = near.filter { niceWidths.contains($0.width) }
            let pool = !nice.isEmpty ? nice : (!near.isEmpty ? near : sizes)
            return pool.min { abs(Double($0.width) - target) < abs(Double($1.width) - target) }!
        }

        let base = Double(defaultMode.width)
        var result: [DisplayMode] = [defaultMode]
        for factor in [0.66, 0.82, 1.2, 1.45, 0.74, 0.9, 1.1, 1.3, 0.58, 1.6] where result.count < 5 {
            let mode = pick(base * factor)
            if !result.contains(where: { $0.sizeLabel == mode.sizeLabel }) { result.append(mode) }
        }
        if !result.contains(where: { $0.sizeLabel == current.sizeLabel }),
           let replace = result.indices.filter({ result[$0].id != defaultMode.id })
               .min(by: { abs(result[$0].width - current.width) < abs(result[$1].width - current.width) }) {
            result[replace] = current
        }
        return (result.sorted { $0.width < $1.width }, defaultMode.id)
    }

    private static func defaultMode(_ sizes: [DisplayMode], all: [DisplayMode], current: DisplayMode) -> DisplayMode {
        if let flagged = sizes.first(where: \.isDefault) { return flagged }
        if let flagged = all.first(where: \.isDefault),
           let match = sizes.first(where: { $0.sizeLabel == flagged.sizeLabel }) { return match }
        // No flag (e.g. modes added by a HiDPI unlock): 4K+ panels default to half their pixels, smaller ones to native.
        let nativeWidth = Double(all.map(\.pixelWidth).max() ?? current.pixelWidth)
        let target = current.isHiDPI && nativeWidth >= 3000 ? nativeWidth / 2 : nativeWidth
        return sizes.min { abs(Double($0.width) - target) < abs(Double($1.width) - target) }!
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

    /// Brightness keys: handles displays macOS can't (or everything when synced). Returns false to let macOS handle it.
    func handleBrightnessKey(up: Bool, fine: Bool) -> Bool {
        guard useBrightnessKeys, let display = displayUnderMouse() else { return false }
        if !syncBrightness && BrightnessController.shared.method(for: display) == .native { return false }
        let step = fine ? brightnessStep / 4 : brightnessStep
        adjustBrightness(by: up ? step : -step, on: display)
        return true
    }

    private func adjustBrightness(by delta: Double, on display: CGDirectDisplayID) {
        let current = BrightnessController.shared.targetBrightness(for: display)
        // Snap to the step grid so repeated presses land on even values.
        let step = abs(delta)
        let steps = ((current + delta) / step).rounded()
        let value = min(max(steps * step, 0), 1)
        setBrightness(value, for: display, animated: true)
        let symbol = value < 0.01 ? "sun.min" : value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        HUD.shared.show(symbol: symbol, title: syncBrightness ? "All Displays" : name(for: display), value: value, on: display)
    }

    private func cycleResolution(_ direction: Int, on display: CGDirectDisplayID) {
        guard let current = pendingModes[display] ?? DisplayModes.current(for: display) else { return }
        let candidates = Self.presets(DisplayModes.list(for: display), current: current).modes

        guard let index = candidates.firstIndex(where: { $0.width == current.width && $0.height == current.height }) else { return }
        let next = index + direction
        guard candidates.indices.contains(next) else {
            HUD.shared.show(symbol: "rectangle.dashed", title: current.sizeLabel,
                            subtitle: direction > 0 ? "Largest resolution" : "Smallest resolution", on: display)
            return
        }
        let mode = candidates[next]
        let isDefault = mode.id == Self.presets(DisplayModes.list(for: display), current: current).defaultID
        var detail = isDefault ? "Default" : (mode.isHiDPI ? "HiDPI" : "Low resolution")
        if mode.refreshRate > 0 { detail += " · \(Int(mode.refreshRate.rounded())) Hz" }
        HUD.shared.show(symbol: direction > 0 ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                        title: mode.sizeLabel, subtitle: detail, on: display)
        // Let the indicator appear before the (briefly blocking) reconfiguration.
        pendingModes[display] = mode
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard self.pendingModes[display]?.id == mode.id else { return } // superseded by a newer press
            DisplayModes.apply(mode, to: display)
            self.pendingModes[display] = nil
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
