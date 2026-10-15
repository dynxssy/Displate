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
        let history: [Double] = (0..<90).map { index in
            let t = Double(index)
            let trend: Double = 52 + 19 * t / 89
            return trend + 2.5 * sin(t / 6)
        }

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

        // Marketing shots: panel only, transparent around it.
        isRenderingPreview = true
        model.dismissWelcome()
        model.loadPreview(temperatures: temperatures, fans: fans, history: history, mode: .curve, helper: .ready)
        for scheme in [ColorScheme.dark, .light] {
            render(marketingShot(MenuView(model: model), scheme: scheme),
                   to: directory.appendingPathComponent("shot-\(scheme == .dark ? "dark" : "light").png"))
        }

        model.loadPreview(temperatures: temperatures, fans: [], history: history, mode: .auto, helper: .notInstalled)
        render(MenuView(model: model).background(Color(white: 0.17)).environment(\.colorScheme, .dark),
               to: directory.appendingPathComponent("menu-fanless.png"))
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
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        print("preview: wrote \(url.lastPathComponent)")
    }
}
