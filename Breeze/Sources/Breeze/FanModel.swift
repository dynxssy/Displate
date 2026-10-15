import AppKit
import FanCore
import ServiceManagement
import SwiftUI

enum FanMode: String, CaseIterable, Identifiable {
    case auto, fixed, curve
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .fixed: return "Fixed"
        case .curve: return "Curve"
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case temperature, rpm, icon
    var id: String { rawValue }
    var title: String {
        switch self {
        case .temperature: return "Temperature"
        case .rpm: return "Fan speed"
        case .icon: return "Icon only"
        }
    }
}

enum HelperState: Equatable {
    case notInstalled, outdated, ready, failed(String)
}

extension SensorKind {
    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .other: return "Hottest"
        }
    }
}

@MainActor
final class FanModel: ObservableObject {
    static let shared = FanModel()

    private enum Keys {
        static let mode = "mode"
        static let fixedSpeed = "fixedSpeed"
        static let curve = "curve"
        static let menuBarStyle = "menuBarStyle"
        static let fahrenheit = "fahrenheit"
        static let welcomeDismissed = "welcomeDismissed"
    }

    @Published private(set) var fans: [FanInfo] = []
    @Published private(set) var temperatures = Temperatures()
    @Published private(set) var history: [Double] = []
    @Published private(set) var helperState: HelperState = .notInstalled
    @Published private(set) var hasReading = false
    @Published private(set) var appliedSpeed: Double?
    @Published private(set) var showWelcome = !UserDefaults.standard.bool(forKey: Keys.welcomeDismissed)

    @Published var mode: FanMode = FanMode(rawValue: UserDefaults.standard.string(forKey: Keys.mode) ?? "") ?? .auto {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode)
            smoothed = nil
            if mode == .auto {
                appliedSpeed = nil
                Task { _ = await HelperClient.shared.setAutomatic() }
            } else {
                control()
            }
        }
    }

    @Published var fixedSpeed: Double = UserDefaults.standard.object(forKey: Keys.fixedSpeed) as? Double ?? 0.5 {
        didSet {
            UserDefaults.standard.set(fixedSpeed, forKey: Keys.fixedSpeed)
            scheduleControl()
        }
    }

    @Published var curve: FanCurve = {
        if let data = UserDefaults.standard.data(forKey: Keys.curve), let curve = try? JSONDecoder().decode(FanCurve.self, from: data) {
            return curve
        }
        return .balanced
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(curve) { UserDefaults.standard.set(data, forKey: Keys.curve) }
            scheduleControl()
        }
    }

    @Published var menuBarStyle = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: Keys.menuBarStyle) ?? "") ?? .temperature {
        didSet {
            UserDefaults.standard.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle)
            StatusBarController.shared.updateTitle()
        }
    }

    @Published var useFahrenheit = UserDefaults.standard.bool(forKey: Keys.fahrenheit) {
        didSet {
            UserDefaults.standard.set(useFahrenheit, forKey: Keys.fahrenheit)
            StatusBarController.shared.updateTitle()
        }
    }

    @Published var launchAtLogin = false {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Breeze: launch at login failed: \(error)")
            }
        }
    }

    private var timer: Timer?
    private var smoothed: Double?
    private var controlTask: Task<Void, Never>?
    private var reading = false
    private let readQueue = DispatchQueue(label: "Breeze.read", qos: .utility)
    private static let historyLength = 90

    var hasFans: Bool { !fans.isEmpty }

    var controlTemperature: Double? {
        switch curve.sensor {
        case .cpu: return temperatures.cpu ?? temperatures.hottest
        case .gpu: return temperatures.gpu ?? temperatures.hottest
        case .other: return temperatures.hottest
        }
    }

    var averageFanFraction: Double {
        fans.isEmpty ? 0 : fans.map(\.fraction).reduce(0, +) / Double(fans.count)
    }

    // MARK: Lifecycle

    func start() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refresh()
        checkHelper()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                FanModel.shared.refresh()
                FanModel.shared.control()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        if mode != .auto { HelperClient.shared.setAutomaticBlocking() }
    }

    func refresh() {
        guard !reading else { return }
        reading = true
        readQueue.async {
            let temperatures = TemperatureMonitor.shared.read()
            let fans = FanReader.fans()
            Task { @MainActor in
                let model = FanModel.shared
                model.reading = false
                model.apply(temperatures: temperatures, fans: fans)
            }
        }
    }

    private func apply(temperatures: Temperatures, fans: [FanInfo]) {
        withAnimation(.smooth(duration: 0.4)) {
            self.temperatures = temperatures
            self.fans = fans
            hasReading = true
        }
        if let value = temperatures.cpu ?? temperatures.hottest {
            history.append(value)
            if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
        }
        StatusBarController.shared.updateTitle()
    }

    /// Used by `--render-preview`.
    func loadPreview(temperatures: Temperatures, fans: [FanInfo], history: [Double], mode: FanMode, helper: HelperState) {
        self.temperatures = temperatures
        self.fans = fans
        self.history = history
        self.mode = mode
        self.helperState = helper
        self.hasReading = true
        self.appliedSpeed = mode == .curve ? curve.speed(at: temperatures.cpu ?? 50) : mode == .fixed ? fixedSpeed : nil
    }

    func dismissWelcome() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showWelcome = false }
        UserDefaults.standard.set(true, forKey: Keys.welcomeDismissed)
    }

    // MARK: Control loop

    /// Target speed (0…1) for the current mode; nil in Auto.
    var desiredSpeed: Double? {
        switch mode {
        case .auto: return nil
        case .fixed: return fixedSpeed
        case .curve:
            guard let temperature = controlTemperature else { return nil }
            return curve.speed(at: temperature)
        }
    }

    private func scheduleControl() {
        controlTask?.cancel()
        controlTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self.control(immediate: true)
        }
    }

    /// Runs every 2 s (also the helper's heartbeat). Curve changes are smoothed: up fast, down slowly.
    func control(immediate: Bool = false) {
        guard mode != .auto, hasFans, var target = desiredSpeed else { return }
        guard helperState == .ready else { return }
        if mode == .curve && !immediate, let previous = smoothed {
            let rate = target > previous ? 0.6 : 0.2
            target = previous + (target - previous) * rate
        }
        smoothed = target
        withAnimation(.smooth(duration: 0.3)) { appliedSpeed = target }

        let commands = fans.map { ($0.index, $0.rpm(forFraction: target)) }
        Task { @MainActor in
            for (index, rpm) in commands {
                let ok = await HelperClient.shared.setFan(index, rpm: rpm)
                if !ok {
                    self.checkHelper()
                    return
                }
            }
        }
    }

    // MARK: Helper

    func checkHelper() {
        guard HelperClient.shared.isInstalled else {
            helperState = .notInstalled
            return
        }
        Task { @MainActor in
            let version = await HelperClient.shared.version()
            withAnimation(.snappy) {
                if version == HelperConstants.version {
                    self.helperState = .ready
                } else if version == nil {
                    self.helperState = .failed("The helper isn't responding. Reinstall it from Settings.")
                } else {
                    self.helperState = .outdated
                }
            }
            if self.helperState == .ready { self.control(immediate: true) }
        }
    }

    func installHelper() {
        if let error = HelperClient.shared.install() {
            if !error.localizedCaseInsensitiveContains("cancel") {
                withAnimation(.snappy) { helperState = .failed(error) }
            }
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.checkHelper()
        }
    }

    func uninstallHelper() {
        Task { _ = await HelperClient.shared.setAutomatic() }
        if let error = HelperClient.shared.uninstall(), !error.localizedCaseInsensitiveContains("cancel") {
            withAnimation(.snappy) { helperState = .failed(error) }
            return
        }
        withAnimation(.snappy) { helperState = .notInstalled }
    }

    // MARK: Formatting

    func format(_ celsius: Double?) -> String {
        formatTemperature(celsius, fahrenheit: useFahrenheit)
    }
}

func formatTemperature(_ celsius: Double?, fahrenheit: Bool) -> String {
    guard let celsius else { return "–" }
    let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
    return "\(Int(value.rounded()))°"
}

extension Double {
    var rpmString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: self.rounded())) ?? "\(Int(self))") + " rpm"
    }
}
