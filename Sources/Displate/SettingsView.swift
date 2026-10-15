import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            GeneralSettings(state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings(state: state)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500)
        .tint(.brand)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $state.launchAtLogin)
                Toggle("Show on-screen indicator", isOn: $state.showHUD)
            }
            Section {
                Toggle("Use brightness keys (F1/F2) for external displays", isOn: $state.useBrightnessKeys)
                if state.useBrightnessKeys && !state.accessibilityGranted {
                    HStack {
                        Label("Needs Accessibility access", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Allow…") { state.requestAccessibility() }
                    }
                }
                Toggle("Sync brightness across displays", isOn: $state.syncBrightness)
                Picker("Shortcut step", selection: $state.brightnessStep) {
                    Text("5%").tag(0.05)
                    Text("6.25% (16 steps)").tag(0.0625)
                    Text("10%").tag(0.1)
                }
            } header: {
                Text("Brightness")
            } footer: {
                Text("Brightness keys adjust the display under the pointer. Hold ⌥⇧ for finer steps.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show low resolution duplicates in All modes", isOn: $state.showAllModes)
            } header: {
                Text("Resolutions")
            } footer: {
                Text("External monitor without HiDPI modes? Open its card in the menu and choose “Unlock HiDPI modes…”.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ShortcutSettings: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    HStack {
                        Image(systemName: action.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(action: action, state: state)
                    }
                }
            } footer: {
                HStack {
                    Text("Shortcuts act on the display under the mouse pointer.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { state.resetShortcuts() }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 10) {
            AppBadge(size: 84)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                .padding(.top, 8)
            Text("Displate")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Version \(version)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Brightness, resolution and HiDPI control for every display — from the menu bar or your keyboard.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}

private struct ShortcutRecorder: View {
    let action: HotkeyAction
    @ObservedObject var state: AppState
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type shortcut…" : (state.shortcuts[action]?.displayString ?? "Record Shortcut"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(recording ? Color.brand : (state.shortcuts[action] == nil ? Color.secondary : Color.primary))
                    .frame(minWidth: 110)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(recording ? Color.brand : Color.primary.opacity(0.1), lineWidth: recording ? 1.5 : 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.15), value: recording)

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
