import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(action: action, state: state)
                    }
                }
                Button("Restore Default Shortcuts") { state.resetShortcuts() }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Shortcuts act on the display under the mouse pointer.")
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $state.launchAtLogin)
                Toggle("Show on-screen indicator", isOn: $state.showHUD)
                Toggle("Show low resolution duplicates of HiDPI modes", isOn: $state.showAllModes)
                Picker("Brightness step", selection: $state.brightnessStep) {
                    Text("5%").tag(0.05)
                    Text("6.25% (16 steps)").tag(0.0625)
                    Text("10%").tag(0.1)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ShortcutRecorder: View {
    let action: HotkeyAction
    @ObservedObject var state: AppState
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(recording ? "Type shortcut…" : (state.shortcuts[action]?.displayString ?? "None")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 120)

            if state.shortcuts[action] != nil, !recording {
                Button {
                    state.setShortcut(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        HotkeyManager.shared.unregisterAll() // so existing shortcuts can be re-recorded
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .control, .option]).isEmpty else {
                NSSound.beep() // require at least one of ⌘ ⌃ ⌥
                return nil
            }
            let shortcut = Shortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: Shortcut.carbonModifiers(from: flags),
                keyLabel: Shortcut.keyLabel(for: event)
            )
            state.setShortcut(shortcut, for: action)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        state.registerHotkeys()
    }
}
