import AppKit
import FanCore
import SwiftUI

/// `Breeze --render-preview <dir>` renders the panel with sample data to PNG files and exits (used by CI).
@MainActor
enum PreviewRenderer {
    static func renderIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-preview"), index + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Exercise the real readers so CI catches crashes in them.
        let smc = SMC.shared
        print("preview: SMC available \(smc.isAvailable)")
        if smc.isAvailable {
            let temperatures = TemperatureMonitor.shared.read()
            print("preview: live CPU \(temperatures.cpu.map { String(format: "%.1f", $0) } ?? "-") GPU \(temperatures.gpu.map { String(format: "%.1f", $0) } ?? "-") sensors \(temperatures.sensors.count)")
            print("preview: live fans \(FanReader.fans().map { "\($0.name) \(Int($0.actual))/\(Int($0.minimum))-\(Int($0.maximum))" })")
        }

        let model = FanModel.shared
        let fans = [
            FanInfo(index: 0, actual: 3120, minimum: 1200, maximum: 5700, target: 3100, isManual: true),
            FanInfo(index: 1, actual: 3290, minimum: 1200, maximum: 6100, target: 3300, isManual: true),
        ]
        let temperatures = Temperatures(cpu: 71.4, gpu: 58.2, hottest: 71.4)
        let history = (0..<90).map { 52 + 19 * Double($0) / 89 + 2.5 * sin(Double($0) / 6) }

        for (name, mode) in [("curve", FanMode.curve), ("fixed", FanMode.fixed), ("auto", FanMode.auto)] {
            model.loadPreview(temperatures: temperatures, fans: fans, history: history, mode: mode,
                              helper: mode == .fixed ? .notInstalled : .ready)
            for scheme in [ColorScheme.dark, .light] where !(scheme == .light && mode != .curve) {
                let view = MenuView(model: model)
                    .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.93))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(20)
                    .background(scheme == .dark ? Color(red: 0.07, green: 0.1, blue: 0.16) : Color(red: 0.62, green: 0.74, blue: 0.88))
                    .environment(\.colorScheme, scheme)
                render(view, to: directory.appendingPathComponent("menu-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }

        model.loadPreview(temperatures: temperatures, fans: [], history: history, mode: .auto, helper: .notInstalled)
        render(MenuView(model: model).background(Color(white: 0.17)).environment(\.colorScheme, .dark),
               to: directory.appendingPathComponent("menu-fanless.png"))
        return true
    }

    private static func render<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            print("preview: failed to render \(url.lastPathComponent)")
            return
        }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        print("preview: wrote \(url.lastPathComponent)")
    }
}
