import AppKit
import SwiftUI

/// `Unload --render-preview <dir>` renders the panel with sample data to PNG files and exits (used by CI).
@MainActor
enum PreviewRenderer {
    static func renderIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-preview"), index + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Also exercise the real collectors so CI catches crashes in them.
        let live = SystemMemory.snapshot()
        let liveGroups = ProcessScanner.shared.scan(includeOtherUsers: true)
        print("preview: live memory \(live.used.memoryString) of \(live.total.memoryString), pressure \(live.pressure.label), gpu \(live.gpuInUse?.memoryString ?? "n/a")")
        print("preview: live top processes \(liveGroups.prefix(8).map { "\($0.name) \($0.footprint.memoryString)" })")

        let model = AppModel.shared
        model.loadPreview(memory: sampleMemory(), history: sampleHistory(), groups: sampleGroups(), models: sampleModels())

        for (suffix, expanded) in [("", false), ("-expanded", true)] {
            model.showAll = expanded
            for scheme in [ColorScheme.dark, .light] where !(expanded && scheme == .light) {
                let view = MenuView(model: model)
                    .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.93))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(20)
                    .background(scheme == .dark ? Color(red: 0.07, green: 0.1, blue: 0.15) : Color(red: 0.6, green: 0.75, blue: 0.85))
                    .environment(\.colorScheme, scheme)
                render(view, to: directory.appendingPathComponent("menu-\(scheme == .dark ? "dark" : "light")\(suffix).png"))
            }
        }

        let hud = HUDModel()
        hud.symbol = "checkmark.circle.fill"
        hud.title = "Freed 7.8 GB"
        hud.subtitle = "mlx_lm.server"
        hud.visible = true
        render(HUDView(model: hud, solidBackground: true).frame(width: 340, height: 110)
            .background(Color(red: 0.25, green: 0.35, blue: 0.5)), to: directory.appendingPathComponent("hud.png"))
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

    private static let gb: UInt64 = 1 << 30

    private static func sampleMemory() -> MemorySnapshot {
        var memory = MemorySnapshot()
        memory.total = 64 * gb
        memory.app = 31 * gb
        memory.wired = 6 * gb
        memory.compressed = 7 * gb
        memory.cached = 12 * gb
        memory.swapUsed = 2 * gb
        memory.gpuInUse = 18 * gb
        memory.pressure = .warning
        return memory
    }

    private static func sampleHistory() -> [Double] {
        (0..<60).map { index in
            let t = Double(index) / 59
            return 0.42 + 0.26 * t + 0.03 * sin(t * 18)
        }
    }

    private static func sampleModels() -> [LoadedModel] {
        [LoadedModel(name: "qwen3:32b", size: 21 * gb, source: .ollama)]
    }

    private static func sampleGroups() -> [ProcessGroup] {
        var nextPID: pid_t = 4000
        func group(_ name: String, bundle: String?, sizes: [Double], ai: Bool = false, detail: String? = nil,
                   system: Bool = false, protected: Bool = false, mapped: Double = 0) -> ProcessGroup {
            let processes = sizes.enumerated().map { index, size -> ProcessEntry in
                nextPID += 7
                let processName = index == 0 ? name : "\(name) Helper"
                let extra = index == 0 ? UInt64(mapped * Double(gb)) : 0
                return ProcessEntry(pid: nextPID, name: processName, path: bundle.map { "\($0)/Contents/MacOS/\(processName)" } ?? "/usr/local/bin/\(name)",
                                    footprint: UInt64(size * Double(gb)) + extra, mapped: extra, isOtherUser: system,
                                    detail: index == 0 ? detail : nil, isAI: ai)
            }
            let id = bundle ?? "pid:\(processes[0].pid)"
            return ProcessGroup(id: id, name: detail ?? name, bundlePath: bundle, bundleID: nil,
                                processes: processes, footprint: processes.reduce(0) { $0 + $1.footprint },
                                isAI: ai, isProtected: protected, isOtherUser: system)
        }
        return [
            group("llama-server", bundle: nil, sizes: [1.6], ai: true, mapped: 13.2),
            group("python3.11", bundle: nil, sizes: [7.8], ai: true, detail: "mlx_lm.server"),
            group("Google Chrome", bundle: "/Applications/Google Chrome.app", sizes: [1.1, 0.9, 0.6, 0.5, 0.3]),
            group("Xcode", bundle: "/Applications/Xcode.app", sizes: [2.4]),
            group("WindowServer", bundle: nil, sizes: [1.2], system: true, protected: true),
            group("Safari", bundle: "/Applications/Safari.app", sizes: [0.6, 0.3]),
            group("node", bundle: nil, sizes: [0.7], detail: "vite.js"),
            group("Finder", bundle: "/System/Library/CoreServices/Finder.app", sizes: [0.35]),
            group("Messages", bundle: "/System/Applications/Messages.app", sizes: [0.25]),
            group("mds_stores", bundle: nil, sizes: [0.2], system: true),
        ].sorted { $0.footprint > $1.footprint }
    }
}
