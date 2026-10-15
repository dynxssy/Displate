import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: FanModel

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
                    Picker("Temperature unit", selection: $model.useFahrenheit) {
                        Text("Celsius (°C)").tag(false)
                        Text("Fahrenheit (°F)").tag(true)
                    }
                }
                Section {
                    HStack {
                        Label(helperStatus, systemImage: helperIcon)
                            .foregroundStyle(model.helperState == .ready ? .green : .secondary)
                        Spacer()
                        if model.helperState == .ready {
                            Button("Uninstall…") { model.uninstallHelper() }
                        } else {
                            Button(model.helperState == .notInstalled ? "Install…" : "Reinstall…") { model.installHelper() }
                        }
                    }
                } header: {
                    Text("Fan control helper")
                } footer: {
                    Text("Changing fan speed needs root, so Breeze installs a small helper in /Library/PrivilegedHelperTools. It only accepts commands from Breeze, keeps speeds within each fan's limits, and returns fans to automatic if Breeze quits or stops responding.")
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
    }

    private var helperStatus: String {
        switch model.helperState {
        case .ready: return "Installed and running"
        case .notInstalled: return "Not installed"
        case .outdated: return "Needs an update"
        case .failed: return "Not responding"
        }
    }

    private var helperIcon: String {
        model.helperState == .ready ? "checkmark.seal.fill" : "lock.shield"
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
            Text("Breeze")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Version \(version)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Temperatures and fan control for your Mac — automatic, fixed, or following a curve you draw.")
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
