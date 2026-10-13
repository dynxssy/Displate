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

        for scheme in [ColorScheme.dark, .light] {
            let view = MenuView(state: state)
                .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.93))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(20)
                .background(scheme == .dark ? Color(red: 0.08, green: 0.1, blue: 0.16) : Color(red: 0.6, green: 0.7, blue: 0.85))
                .environment(\.colorScheme, scheme)
            render(view, to: directory.appendingPathComponent("menu-\(scheme == .dark ? "dark" : "light").png"))
        }
        return true
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
        func modes(native: (Int, Int), hiDPI: Bool, step: Int, rates: [Double], defaultWidth: Int?) -> [DisplayMode] {
            var result: [DisplayMode] = []
            let aspect = Double(native.0) / Double(native.1)
            var width = hiDPI ? native.0 / 4 : 800
            let maxWidth = hiDPI ? native.0 / 2 * 3 / 2 : native.0
            while width <= maxWidth {
                let height = Int((Double(width) / aspect).rounded())
                for rate in rates {
                    result.append(DisplayMode(id: nextID, width: width, height: height,
                                              pixelWidth: hiDPI ? width * 2 : width, pixelHeight: hiDPI ? height * 2 : height,
                                              refreshRate: rate, isDefault: width == defaultWidth))
                    nextID += 1
                }
                width += step
            }
            return result
        }

        let builtIn = modes(native: (3024, 1964), hiDPI: true, step: 16, rates: [120], defaultWidth: 1512)
        let external = modes(native: (3840, 2160), hiDPI: true, step: 16, rates: [60, 120, 144], defaultWidth: 1920)
        let builtInCurrent = builtIn.first { $0.width == 1512 }
        let externalCurrent = external.first { $0.width == 2560 && $0.refreshRate == 144 }
        let builtInPresets = AppState.presets(builtIn, current: builtInCurrent)
        let externalPresets = AppState.presets(external, current: externalCurrent)

        return [
            DisplayInfo(id: 1, name: "Built-in Retina Display", isBuiltIn: true, isMain: true, brightness: 0.72,
                        brightnessMethod: .native, hasDDC: false, softwareDimmingForced: false, modes: builtIn,
                        currentMode: builtInCurrent, hasHiDPIModes: true, hasOverride: false, contrast: nil,
                        presets: builtInPresets.modes, defaultModeID: builtInPresets.defaultID, refreshRates: [120]),
            DisplayInfo(id: 2, name: "LG HDR 4K", isBuiltIn: false, isMain: false, brightness: 0.45,
                        brightnessMethod: .ddc, hasDDC: true, softwareDimmingForced: false, modes: external,
                        currentMode: externalCurrent, hasHiDPIModes: true, hasOverride: false, contrast: 0.5,
                        presets: externalPresets.modes, defaultModeID: externalPresets.defaultID, refreshRates: [60, 120, 144]),
        ]
    }
}
