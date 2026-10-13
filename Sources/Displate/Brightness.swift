import AppKit
import CoreGraphics

enum BrightnessMethod: String {
    case native = "Built-in"
    case ddc = "DDC/CI"
    case software = "Software dimming"
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
    private var forcedSoftware: Set<String>

    private static let forcedSoftwareKey = "forcedSoftwareDimming"

    private init() {
        forcedSoftware = Set(UserDefaults.standard.stringArray(forKey: Self.forcedSoftwareKey) ?? [])
    }

    /// Rescans DDC services when the set of connected external displays changes.
    func updateServices(for displays: [CGDirectDisplayID], names: [CGDirectDisplayID: String]) {
        let externals = displays.filter { CGDisplayIsBuiltin($0) == 0 && !displayServices.canControl($0) }.sorted()
        defer { reapplySoftwareDimming() }
        guard externals != scannedDisplays else { return }
        scannedDisplays = externals

        ddc = [:]
        for (display, service) in DDC.services(for: externals, names: names) {
            let channel = DDCService(service: service)
            ddc[display] = channel
            channel.readBrightness { value in
                guard let value else { return }
                BrightnessController.shared.values[display] = value
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
        if method(for: display) == .native, let value = displayServices.brightness(display) {
            return value
        }
        return values[display] ?? 1
    }

    func setBrightness(_ value: Double, for display: CGDirectDisplayID) {
        let value = min(max(value, 0), 1)
        values[display] = value
        switch method(for: display) {
        case .native: displayServices.setBrightness(value, for: display)
        case .ddc: ddc[display]?.setBrightness(value)
        case .software: applyGamma(value, to: display)
        }
    }

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
}
