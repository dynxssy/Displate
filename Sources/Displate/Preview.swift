import AppKit
import SwiftUI

/// `Displate --render-preview <dir>` renders the panel with sample displays to PNG files and exits.
/// Used by CI to check the layout without real hardware.
@MainActor
enum PreviewRenderer {
    static func renderIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-preview"), index + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let state = AppState.shared
        state.loadPreview(sampleDisplays())

        for (suffix, dismissWelcome) in [("", false), ("-normal", true)] {
            if dismissWelcome { state.dismissWelcome() }
            for scheme in [ColorScheme.dark, .light] where !(dismissWelcome && scheme == .light) {
            let view = MenuView(state: state)
                .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.93))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(20)
                .background(scheme == .dark ? Color(red: 0.08, green: 0.1, blue: 0.16) : Color(red: 0.6, green: 0.7, blue: 0.85))
                .environment(\.colorScheme, scheme)
            render(view, to: directory.appendingPathComponent("menu-\(scheme == .dark ? "dark" : "light")\(suffix).png"))
            }
        }
        for (name, symbol, title, subtitle, value) in [
            ("hud-brightness", "sun.max.fill", "LG HDR 4K", nil as String?, 0.62 as Double?),
            ("hud-resolution", "arrow.up.left.and.arrow.down.right", "1920 × 1080", "Default · 144 Hz", nil),
        ] {
            let model = HUDModel()
            model.symbol = symbol
            model.title = title
            model.subtitle = subtitle
            model.value = value
            model.visible = true
            render(HUDView(model: model, solidBackground: true)
                .frame(width: 340, height: 110)
                .background(Color(red: 0.25, green: 0.35, blue: 0.5)), to: directory.appendingPathComponent("\(name).png"))
        }
        // Marketing shots: panel only, transparent around it.
        isRenderingPreview = true
        render(AppBadge(size: 120).padding(4), to: directory.appendingPathComponent("icon.png"))
        state.loadPreview(Array(sampleDisplays().prefix(2)))
        for scheme in [ColorScheme.dark, .light] {
            render(marketingShot(MenuView(state: state), scheme: scheme),
                   to: directory.appendingPathComponent("shot-\(scheme == .dark ? "dark" : "light").png"))
        }
        return true
    }

    static func marketingShot<V: View>(_ view: V, scheme: ColorScheme) -> some View {
        view
            .background(scheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.17) : Color(red: 0.975, green: 0.973, blue: 0.965))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16), radius: 24, y: 12)
            .padding(36)
            .environment(\.colorScheme, scheme)
    }

    private static func render<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            print("preview: failed to render \(url.lastPathComponent)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("preview: wrote \(url.path)")
    }

    private static func sampleDisplays() -> [DisplayInfo] {
        var nextID: Int32 = 1
        func modes(native: (Int, Int), widths: [Int], hiDPI: Bool, rates: [Double], defaultWidth: Int?) -> [DisplayMode] {
            let aspect = Double(native.0) / Double(native.1)
            var result: [DisplayMode] = []
            for width in widths {
                let height = Int((Double(width) / aspect).rounded())
                for rate in rates {
                    result.append(DisplayMode(id: nextID, width: width, height: height,
                                              pixelWidth: hiDPI ? width * 2 : width, pixelHeight: hiDPI ? height * 2 : height,
                                              refreshRate: rate, isDefault: width == defaultWidth))
                    nextID += 1
                }
            }
            return result
        }

        // MacBook Pro 14": macOS offers a handful of scaled modes, 1512 is the default.
        let builtIn = modes(native: (3024, 1964), widths: [1024, 1147, 1352, 1512, 1800], hiDPI: true, rates: [120], defaultWidth: 1512)
            + modes(native: (3024, 1964), widths: [1512, 3024], hiDPI: false, rates: [120], defaultWidth: nil)
        // 4K monitor with many scaled modes.
        let external = modes(native: (3840, 2160), widths: Array(stride(from: 960, through: 3840, by: 16)), hiDPI: true, rates: [60, 120, 144], defaultWidth: 1920)
            + modes(native: (3840, 2160), widths: [1920, 2560, 3840], hiDPI: false, rates: [60, 120, 144], defaultWidth: nil)
        // 1440p monitor after "Unlock HiDPI modes": dense list, no default flag (the user's case).
        let unlocked = modes(native: (2560, 1440), widths: [800, 840, 960] + Array(stride(from: 1024, through: 2544, by: 16)), hiDPI: true, rates: [144], defaultWidth: nil)
            + modes(native: (2560, 1440), widths: [1280, 1920, 2560], hiDPI: false, rates: [144], defaultWidth: nil)

        func info(_ id: CGDirectDisplayID, _ name: String, builtIn isBuiltIn: Bool, modes: [DisplayMode], currentWidth: Int,
                  rate: Double, brightness: Double, contrast: Double?) -> DisplayInfo {
            let current = modes.first { $0.isHiDPI && $0.width == currentWidth && $0.refreshRate == rate }
            let presets = AppState.presets(modes, current: current)
            print("preview: \(name) presets \(presets.modes.map(\.sizeLabel)) default \(presets.modes.first { $0.id == presets.defaultID }?.sizeLabel ?? "-")")
            let rates = Array(Set(modes.filter { $0.width == currentWidth && $0.isHiDPI }.map(\.refreshRate))).sorted()
            return DisplayInfo(id: id, name: name, isBuiltIn: isBuiltIn, isMain: id == 1, brightness: brightness,
                               brightnessMethod: isBuiltIn ? .native : .ddc, hasDDC: !isBuiltIn, softwareDimmingForced: false,
                               modes: DisplayModes.withoutLowResolutionDuplicates(modes), currentMode: current, hasHiDPIModes: true,
                               hasOverride: false, contrast: contrast, presets: presets.modes, defaultModeID: presets.defaultID,
                               refreshRates: rates)
        }

        return [
            info(1, "Built-in Retina Display", builtIn: true, modes: builtIn, currentWidth: 1512, rate: 120, brightness: 0.72, contrast: nil),
            info(2, "LG HDR 4K", builtIn: false, modes: external, currentWidth: 2560, rate: 144, brightness: 0.45, contrast: 0.5),
            info(3, "Q27 (HiDPI unlocked)", builtIn: false, modes: unlocked, currentWidth: 2304, rate: 144, brightness: 0.8, contrast: nil),
        ]
    }
}
