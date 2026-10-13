import AppKit
import CoreGraphics

/// HiDPI fix without virtual displays:
/// - `toggle` switches the current resolution between its HiDPI (2x) and low resolution variant.
/// - `installOverride` writes a macOS display override with HiDPI "scale-resolutions" so monitors
///   that macOS treats as low DPI get HiDPI modes (takes effect after reconnecting / logging out).
enum HiDPI {
    enum ToggleResult {
        case switched(DisplayMode)
        case unavailable
    }

    static func hasHiDPIModes(_ display: CGDirectDisplayID) -> Bool {
        DisplayModes.list(for: display).contains(where: \.isHiDPI)
    }

    static func isActive(_ display: CGDirectDisplayID) -> Bool {
        DisplayModes.current(for: display)?.isHiDPI ?? false
    }

    static func toggle(_ display: CGDirectDisplayID) -> ToggleResult {
        guard let current = DisplayModes.current(for: display) else { return .unavailable }
        let candidates = DisplayModes.list(for: display).filter { $0.isHiDPI != current.isHiDPI }
        guard !candidates.isEmpty else { return .unavailable }

        let target: DisplayMode?
        if current.isHiDPI {
            // HiDPI -> the same size in low resolution, else the native size.
            target = candidates.first { $0.width == current.width && $0.height == current.height && sameRate($0, current) }
                ?? candidates.first { $0.width == current.width && $0.height == current.height }
                ?? candidates.max { $0.width * $0.height < $1.width * $1.height }
        } else {
            // Low res -> HiDPI with the same "looks like" size, else the closest one.
            target = candidates.first { $0.width == current.width && $0.height == current.height && sameRate($0, current) }
                ?? candidates.min { distance($0, current) < distance($1, current) }
        }
        guard let target, DisplayModes.apply(target, to: display) else { return .unavailable }
        return .switched(target)
    }

    private static func sameRate(_ a: DisplayMode, _ b: DisplayMode) -> Bool {
        abs(a.refreshRate - b.refreshRate) < 1
    }

    private static func distance(_ a: DisplayMode, _ b: DisplayMode) -> Int {
        abs(a.width - b.width) + abs(a.height - b.height) + (sameRate(a, b) ? 0 : 1)
    }

    // MARK: Display override

    private static let overridesRoot = "/Library/Displays/Contents/Resources/Overrides"

    private static func overridePath(for display: CGDirectDisplayID) -> (directory: String, file: String) {
        let vendor = String(CGDisplayVendorNumber(display), radix: 16)
        let product = String(CGDisplayModelNumber(display), radix: 16)
        let directory = "\(overridesRoot)/DisplayVendorID-\(vendor)"
        return (directory, "\(directory)/DisplayProductID-\(product)")
    }

    static func hasOverride(_ display: CGDirectDisplayID) -> Bool {
        FileManager.default.fileExists(atPath: overridePath(for: display).file)
    }

    /// Asks for an administrator password and installs the override. Returns an error message on failure.
    static func installOverride(for display: CGDirectDisplayID, name: String) -> String? {
        let native = DisplayModes.list(for: display).max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
        guard let native else { return "Could not read the display's modes." }

        let resolutions = scaledSizes(width: native.pixelWidth, height: native.pixelHeight).map { size -> Data in
            // Each entry: pixel width, pixel height (big-endian UInt32) + HiDPI flags.
            var words: [UInt32] = [UInt32(size.width * 2), UInt32(size.height * 2), 0x0000_0001, 0x0020_0000]
            words = words.map(\.bigEndian)
            return words.withUnsafeBytes { Data($0) }
        }
        let plist: [String: Any] = [
            "DisplayProductName": "\(name) (Displate HiDPI)",
            "DisplayVendorID": Int(CGDisplayVendorNumber(display)),
            "DisplayProductID": Int(CGDisplayModelNumber(display)),
            "scale-resolutions": resolutions,
        ]

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("displate-override-\(UUID().uuidString).plist")
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: temp)
        } catch {
            return error.localizedDescription
        }
        defer { try? FileManager.default.removeItem(at: temp) }

        let path = overridePath(for: display)
        let command = "mkdir -p \(quoted(path.directory)) && cp \(quoted(temp.path)) \(quoted(path.file)) && chown root:wheel \(quoted(path.file)) && chmod 644 \(quoted(path.file))"
        return runAsAdmin(command)
    }

    static func removeOverride(for display: CGDirectDisplayID) -> String? {
        runAsAdmin("rm -f \(quoted(overridePath(for: display).file))")
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAsAdmin(_ command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        if let error {
            return error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        }
        return nil
    }

    /// "Looks like" sizes (points) to offer, keeping the monitor's aspect ratio.
    static func scaledSizes(width: Int, height: Int) -> [(width: Int, height: Int)] {
        let aspect = Double(width) / Double(height)
        let common = [1024, 1152, 1280, 1344, 1440, 1512, 1600, 1680, 1728, 1792, 1800, 1920, 2048,
                      2240, 2304, 2400, 2560, 2880, 3008, 3200, 3360, 3440, 3840]
        var widths = Set(common.filter { $0 < width && Double($0) >= Double(width) * 0.5 })
        for factor in [0.9, 0.8, 0.75, 2.0 / 3.0, 0.6, 0.5] {
            widths.insert(Int(Double(width) * factor) & ~1)
        }

        var seen: Set<String> = ["\(width)x\(height)"]
        var result: [(width: Int, height: Int)] = [(width, height)]
        for w in widths.sorted(by: >) {
            let h = Int((Double(w) / aspect).rounded()) & ~1
            guard h > 0, seen.insert("\(w)x\(h)").inserted else { continue }
            result.append((w, h))
        }
        return result
    }
}
