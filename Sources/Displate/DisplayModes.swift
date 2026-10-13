import AppKit
import CoreGraphics

struct DisplayMode: Identifiable, Hashable {
    let id: Int32          // ioDisplayModeID
    let width: Int         // points
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    /// macOS' own "Default" mode (kDisplayModeDefaultFlag), as shown in System Settings.
    let isDefault: Bool

    var isHiDPI: Bool { pixelWidth > width }

    var sizeLabel: String { "\(width) × \(height)" }

    var label: String {
        var text = sizeLabel
        if isHiDPI { text += " HiDPI" }
        if refreshRate > 0 { text += " @ \(Int(refreshRate.rounded()))Hz" }
        return text
    }

    init(id: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double, isDefault: Bool = false) {
        self.id = id
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.isDefault = isDefault
    }

    init(_ mode: CGDisplayMode) {
        id = mode.ioDisplayModeID
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
        isDefault = mode.ioFlags & 0x0000_0004 != 0
    }
}

enum DisplayModes {
    private static var options: CFDictionary {
        [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
    }

    private static func cgModes(for display: CGDirectDisplayID) -> [CGDisplayMode] {
        (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
    }

    /// All desktop-usable modes, largest first, without exact duplicates.
    static func list(for display: CGDirectDisplayID) -> [DisplayMode] {
        var seen = Set<String>()
        return cgModes(for: display)
            .filter { $0.isUsableForDesktopGUI() }
            .map(DisplayMode.init)
            .filter { seen.insert("\($0.width)x\($0.height)/\($0.pixelWidth)x\($0.pixelHeight)@\(Int($0.refreshRate.rounded()))").inserted }
            .sorted {
                ($0.width, $0.height, $0.isHiDPI ? 1 : 0, $0.refreshRate) >
                ($1.width, $1.height, $1.isHiDPI ? 1 : 0, $1.refreshRate)
            }
    }

    /// Hides low resolution modes that also exist as HiDPI.
    static func withoutLowResolutionDuplicates(_ modes: [DisplayMode]) -> [DisplayMode] {
        let hiDPISizes = Set(modes.filter(\.isHiDPI).map { "\($0.width)x\($0.height)@\(Int($0.refreshRate.rounded()))" })
        return modes.filter { $0.isHiDPI || !hiDPISizes.contains("\($0.width)x\($0.height)@\(Int($0.refreshRate.rounded()))") }
    }

    static func current(for display: CGDirectDisplayID) -> DisplayMode? {
        CGDisplayCopyDisplayMode(display).map(DisplayMode.init)
    }

    @discardableResult
    static func apply(_ mode: DisplayMode, to display: CGDirectDisplayID) -> Bool {
        guard let cgMode = cgModes(for: display).first(where: { $0.ioDisplayModeID == mode.id }) else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        _ = CGConfigureDisplayWithDisplayMode(config, display, cgMode, nil)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Stable identifier for a physical display across reboots and reconnects.
    static func persistentKey(for display: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(display))-\(CGDisplayModelNumber(display))-\(CGDisplaySerialNumber(display))"
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
