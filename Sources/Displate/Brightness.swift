import AppKit
import CoreGraphics

enum BrightnessMethod: String {
    case native = "Built-in"
    case ddc = "DDC/CI"
    case software = "Software"
}

/// Built-in / Apple display brightness through the DisplayServices framework.
struct DisplayServices {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanFn = @convention(c) (CGDirectDisplayID) -> Bool

    private let getFn: GetFn?
    private let setFn: SetFn?
    private let canFn: CanFn?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        func symbol<T>(_ name: String) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        getFn = symbol("DisplayServicesGetBrightness")
        setFn = symbol("DisplayServicesSetBrightness")
        canFn = symbol("DisplayServicesCanChangeBrightness")
    }

    func canControl(_ display: CGDirectDisplayID) -> Bool {
        guard let getFn else { return false }
        if let canFn, canFn(display) { return true }
        var value: Float = 0
        return CGDisplayIsBuiltin(display) != 0 && getFn(display, &value) == 0
    }

    func brightness(_ display: CGDirectDisplayID) -> Double? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? Double(value) : nil
    }

    func setBrightness(_ value: Double, for display: CGDirectDisplayID) {
        _ = setFn?(display, Float(value))
    }
}

@MainActor
final class BrightnessController {
    static let shared = BrightnessController()

    private let displayServices = DisplayServices()
    private var ddc: [CGDirectDisplayID: DDCService] = [:]
    private var scannedDisplays: [CGDirectDisplayID] = []
    private var values: [CGDirectDisplayID: Double] = [:]
    private var contrasts: [CGDirectDisplayID: Double] = [:]
    private var targets: [CGDirectDisplayID: Double] = [:]
    private var animations: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var forcedSoftware: Set<String>

    private static let forcedSoftwareKey = "forcedSoftwareDimming"
    private static let softwareValuesKey = "softwareBrightness"

    private init() {
        forcedSoftware = Set(UserDefaults.standard.stringArray(forKey: Self.forcedSoftwareKey) ?? [])
    }

    /// Rescans DDC services when the set of connected external displays changes.
    func updateServices(for displays: [CGDirectDisplayID], names: [CGDirectDisplayID: String]) {
        let externals = displays.filter { CGDisplayIsBuiltin($0) == 0 && !displayServices.canControl($0) }.sorted()
        defer { reapplySoftwareDimming() }
        guard externals != scannedDisplays else { return }
        scannedDisplays = externals

        // Software dimming levels survive relaunches.
        let saved = UserDefaults.standard.dictionary(forKey: Self.softwareValuesKey) as? [String: Double] ?? [:]
        for display in externals where values[display] == nil {
            values[display] = saved[DisplayModes.persistentKey(for: display)]
        }

        ddc = [:]
        for (display, service) in DDC.services(for: externals, names: names) {
            let channel = DDCService(service: service)
            ddc[display] = channel
            channel.read(DDC.brightnessVCP) { value in
                guard let value else { return }
                BrightnessController.shared.values[display] = value
                AppState.shared.brightnessDidChange(for: display)
            }
            channel.read(DDC.contrastVCP) { value in
                guard let value else { return }
                BrightnessController.shared.contrasts[display] = value
                AppState.shared.brightnessDidChange(for: display)
            }
        }
    }

    func method(for display: CGDirectDisplayID) -> BrightnessMethod {
        if displayServices.canControl(display) { return .native }
        if ddc[display] != nil, !isSoftwareForced(display) { return .ddc }
        return .software
    }

    func hasDDC(_ display: CGDirectDisplayID) -> Bool { ddc[display] != nil }

    func brightness(for display: CGDirectDisplayID) -> Double {
        if animations[display] == nil, method(for: display) == .native, let value = displayServices.brightness(display) {
            return value
        }
        return values[display] ?? 1
    }

    /// The value brightness is heading to (mid-animation), so repeated key presses accumulate.
    func targetBrightness(for display: CGDirectDisplayID) -> Double {
        targets[display] ?? brightness(for: display)
    }

    func setBrightness(_ value: Double, for display: CGDirectDisplayID) {
        animations[display]?.cancel()
        animations[display] = nil
        targets[display] = nil
        write(min(max(value, 0), 1), for: display)
    }

    /// Eases to the new value over ~150 ms. DDC monitors get a single write; they fade on their own.
    func animateBrightness(to value: Double, for display: CGDirectDisplayID) {
        let target = min(max(value, 0), 1)
        let start = values[display] ?? brightness(for: display)
        animations[display]?.cancel()
        guard method(for: display) != .ddc, abs(target - start) > 0.002 else {
            animations[display] = nil
            targets[display] = nil
            write(target, for: display)
            return
        }
        targets[display] = target
        animations[display] = Task { @MainActor [weak self] in
            let frames = 12
            for frame in 1...frames {
                if Task.isCancelled { return }
                let t = Double(frame) / Double(frames)
                let eased = 1 - pow(1 - t, 3)
                self?.write(start + (target - start) * eased, for: display)
                try? await Task.sleep(for: .milliseconds(12))
            }
            if Task.isCancelled { return }
            self?.animations[display] = nil
            self?.targets[display] = nil
        }
    }

    private func write(_ value: Double, for display: CGDirectDisplayID) {
        values[display] = value
        switch method(for: display) {
        case .native:
            displayServices.setBrightness(value, for: display)
        case .ddc:
            ddc[display]?.set(DDC.brightnessVCP, fraction: value)
        case .software:
            applyGamma(value, to: display)
            saveSoftwareValue(value, for: display)
        }
    }

    // MARK: Contrast (DDC only)

    func contrast(for display: CGDirectDisplayID) -> Double? {
        guard ddc[display] != nil else { return nil }
        return contrasts[display] ?? 0.5
    }

    func setContrast(_ value: Double, for display: CGDirectDisplayID) {
        guard let channel = ddc[display] else { return }
        let value = min(max(value, 0), 1)
        contrasts[display] = value
        channel.set(DDC.contrastVCP, fraction: value)
    }

    // MARK: Software dimming

    func isSoftwareForced(_ display: CGDirectDisplayID) -> Bool {
        forcedSoftware.contains(DisplayModes.persistentKey(for: display))
    }

    func setSoftwareForced(_ forced: Bool, for display: CGDirectDisplayID) {
        let key = DisplayModes.persistentKey(for: display)
        if forced { forcedSoftware.insert(key) } else { forcedSoftware.remove(key) }
        UserDefaults.standard.set(Array(forcedSoftware), forKey: Self.forcedSoftwareKey)
        if !forced {
            CGDisplayRestoreColorSyncSettings()
            reapplySoftwareDimming()
        }
        setBrightness(values[display] ?? 1, for: display)
    }

    /// macOS resets gamma tables on reconfiguration, so software dimming is reapplied after refreshes.
    func reapplySoftwareDimming() {
        for (display, value) in values where method(for: display) == .software && value < 1 {
            applyGamma(value, to: display)
        }
    }

    func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
    }

    private func applyGamma(_ value: Double, to display: CGDirectDisplayID) {
        let maximum = CGGammaValue(0.08 + 0.92 * value) // never go fully black
        CGSetDisplayTransferByFormula(display, 0, maximum, 1, 0, maximum, 1, 0, maximum, 1)
    }

    private func saveSoftwareValue(_ value: Double, for display: CGDirectDisplayID) {
        var saved = UserDefaults.standard.dictionary(forKey: Self.softwareValuesKey) as? [String: Double] ?? [:]
        saved[DisplayModes.persistentKey(for: display)] = value
        UserDefaults.standard.set(saved, forKey: Self.softwareValuesKey)
    }
}
