import Combine
import SwiftUI

struct MenuView: View {
    @ObservedObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.displays.isEmpty {
                Text("No displays found").foregroundStyle(.secondary)
            }
            ForEach(state.displays) { display in
                DisplaySection(display: display, state: state)
                Divider()
            }
            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Spacer()
                Button("Quit Displate") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { state.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            state.refresh()
        }
    }
}

private struct DisplaySection: View {
    let display: DisplayInfo
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                Text(display.name).font(.headline).lineLimit(1)
                Spacer()
                if let mode = display.currentMode {
                    Text(mode.isHiDPI ? "\(mode.sizeLabel) HiDPI" : mode.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "sun.min").foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { display.brightness },
                    set: { state.setBrightness($0, for: display.id) }
                ), in: 0...1)
                Image(systemName: "sun.max").foregroundStyle(.secondary)
            }
            Text("Brightness: \(display.brightnessMethod.rawValue)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Resolution", selection: Binding(
                get: { display.currentMode?.id ?? -1 },
                set: { state.applyMode($0, for: display.id) }
            )) {
                ForEach(display.modes) { mode in
                    Text(mode.label).tag(mode.id)
                }
            }

            Toggle("HiDPI", isOn: Binding(
                get: { display.currentMode?.isHiDPI ?? false },
                set: { _ in state.toggleHiDPI(for: display.id) }
            ))
            .disabled(!display.hasHiDPIModes)

            if !display.isBuiltIn {
                if display.hasDDC {
                    Toggle("Use software dimming", isOn: Binding(
                        get: { display.softwareDimmingForced },
                        set: { state.setSoftwareDimming($0, for: display.id) }
                    ))
                }
                if display.hasOverride {
                    Button("Remove HiDPI unlock…") { state.removeHiDPIOverride(for: display.id) }
                        .buttonStyle(.link)
                        .font(.caption)
                } else if !display.hasHiDPIModes {
                    Button("Unlock HiDPI modes…") { state.installHiDPIOverride(for: display.id) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }
}
