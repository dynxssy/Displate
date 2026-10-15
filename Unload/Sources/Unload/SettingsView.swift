import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            Form {
                Section {
                    Toggle("Launch at login", isOn: $model.launchAtLogin)
                    Picker("Menu bar shows", selection: $model.menuBarStyle) {
                        ForEach(MenuBarStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    Toggle("Show a notification pill after freeing memory", isOn: $model.showHUD)
                }
                Section {
                    Toggle("Include system processes", isOn: $model.includeSystemProcesses)
                } footer: {
                    Text("System processes belong to macOS or other users. Quitting one asks for your administrator password. Critical processes like WindowServer are protected.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
            .tabItem { Label("General", systemImage: "gearshape") }

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480)
        .tint(.brand)
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
            Text("Unload")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Version \(version)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Find what's holding your memory — apps, forgotten processes and loaded AI models — and free it in one click.")
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
