import SwiftUI

struct MenuView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 8) {
            header

            if state.showWelcome {
                WelcomeCard(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if state.useBrightnessKeys && !state.accessibilityGranted {
                BrightnessKeysCard(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            if state.displays.isEmpty {
                Text("No displays found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }

            ForEach(state.displays) { display in
                DisplayCard(display: display, state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .padding(10)
        .frame(width: 320)
        .tint(.brand)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: state.displays.map(\.id))
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: state.accessibilityGranted)
    }

    private var header: some View {
        HStack(spacing: 8) {
            AppBadge(size: 22)
            Text("Displate")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if state.displays.count > 1 {
                IconButton(symbol: "link", active: state.syncBrightness,
                           help: state.syncBrightness ? "Brightness is synced across displays" : "Sync brightness across displays") {
                    state.syncBrightness.toggle()
                }
            }
            IconButton(symbol: "gearshape.fill", help: "Settings") {
                SettingsWindowController.shared.show()
            }
            IconButton(symbol: "power", help: "Quit Displate") {
                NSApp.terminate(nil)
            }
        }
        .padding(.leading, 4)
        .padding(.bottom, 2)
    }
}

// MARK: - Onboarding cards

private struct WelcomeCard: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.wave.fill").foregroundStyle(.yellow)
                Text("Displate lives in your menu bar")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                ShortcutHint(keys: state.shortcuts[.brightnessDown].map { "\($0.displayString)  \(state.shortcuts[.brightnessUp]?.displayString ?? "")" } ?? "F1  F2",
                             text: "Brightness")
                ShortcutHint(keys: "\(state.shortcuts[.resolutionPrevious]?.displayString ?? "")  \(state.shortcuts[.resolutionNext]?.displayString ?? "")",
                             text: "Resolution")
                ShortcutHint(keys: state.shortcuts[.toggleHiDPI]?.displayString ?? "", text: "HiDPI")
            }
            HStack {
                if state.useBrightnessKeys && !state.accessibilityGranted {
                    CapsuleButton(title: "Enable F1/F2 keys", prominent: false) { state.requestAccessibility() }
                }
                Spacer()
                CapsuleButton(title: "Got it", prominent: true) { state.dismissWelcome() }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color.orange.opacity(0.16), Color.purple.opacity(0.14)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

private struct ShortcutHint: View {
    let keys: String
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(keys)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
        }
    }
}

private struct BrightnessKeysCard: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Brightness keys")
                    .font(.system(size: 12, weight: .semibold))
                Text("Allow access so F1/F2 work on external displays")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            CapsuleButton(title: "Allow", prominent: true) { state.requestAccessibility() }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.brand.opacity(0.12)))
    }
}

// MARK: - Display card

private struct DisplayCard: View {
    let display: DisplayInfo
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            PillSlider(
                value: Binding(get: { display.brightness }, set: { state.setBrightness($0, for: display.id) }),
                symbol: display.brightness < 0.33 ? "sun.min.fill" : "sun.max.fill",
                tint: .brand
            )
            .help("Brightness (\(display.brightnessMethod.rawValue))")

            if let contrast = display.contrast {
                PillSlider(
                    value: Binding(get: { contrast }, set: { state.setContrast($0, for: display.id) }),
                    symbol: "circle.lefthalf.filled",
                    tint: .indigo
                )
                .help("Contrast")
            }

            if display.presets.count > 1 {
                ResolutionStrip(display: display) { mode in
                    state.applyMode(mode.id, for: display.id)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: display.isBuiltIn ? [.blue, .cyan] : [.purple, .pink],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(display.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(display.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            DisplayMenu(display: display, state: state)
        }
    }
}

/// "⋯" menu with everything that doesn't need to be on screen all the time.
private struct DisplayMenu: View {
    let display: DisplayInfo
    @ObservedObject var state: AppState
    @State private var hovering = false

    var body: some View {
        if isRenderingPreview {
            menuLabel
        } else {
            menu
        }
    }

    private var menuLabel: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0.06)))
            .contentShape(Circle())
    }

    private var menu: some View {
        Menu {
            if display.hasHiDPIModes {
                Toggle("HiDPI", isOn: Binding(
                    get: { display.currentMode?.isHiDPI ?? false },
                    set: { _ in state.toggleHiDPI(for: display.id) }
                ))
            }

            if display.refreshRates.count > 1 {
                Picker("Refresh Rate", selection: Binding(
                    get: { display.currentMode?.refreshRate.rounded() ?? 0 },
                    set: { state.setRefreshRate($0, for: display.id) }
                )) {
                    ForEach(display.refreshRates, id: \.self) { rate in
                        Text("\(Int(rate)) Hz").tag(rate)
                    }
                }
                .pickerStyle(.menu)
            }

            Menu("All Resolutions") {
                ForEach(display.modes) { mode in
                    Toggle(mode.id == display.defaultModeID ? "\(mode.label) (Default)" : mode.label, isOn: Binding(
                        get: { mode.id == display.currentMode?.id },
                        set: { _ in state.applyMode(mode.id, for: display.id) }
                    ))
                }
            }

            if display.hasDDC || !display.isBuiltIn {
                Divider()
            }
            if display.hasDDC {
                Toggle("Software Dimming", isOn: Binding(
                    get: { display.softwareDimmingForced },
                    set: { state.setSoftwareDimming($0, for: display.id) }
                ))
            }
            if !display.isBuiltIn {
                if display.hasOverride {
                    Button("Remove HiDPI Unlock…") { state.removeHiDPIOverride(for: display.id) }
                } else if !display.hasHiDPIModes {
                    Button("Unlock HiDPI Modes…") { state.installHiDPIOverride(for: display.id) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// System Settings style picker: five sizes from "Larger Text" to "More Space".
private struct ResolutionStrip: View {
    let display: DisplayInfo
    let onSelect: (DisplayMode) -> Void
    @State private var hovered: Int32?
    @Namespace private var selection

    private var selectedID: Int32? {
        guard let current = display.currentMode else { return nil }
        return display.presets.first { $0.sizeLabel == current.sizeLabel }?.id
    }

    private var caption: String {
        let id = hovered ?? selectedID
        guard let mode = display.presets.first(where: { $0.id == id }) else { return display.currentMode?.sizeLabel ?? "" }
        return mode.id == display.defaultModeID ? "\(mode.sizeLabel) · Default" : mode.sizeLabel
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(display.presets.enumerated()), id: \.element.id) { index, mode in
                    tile(mode, index: index)
                }
            }
            ZStack {
                HStack {
                    Text("Larger Text")
                    Spacer()
                    Text("More Space")
                }
                .foregroundStyle(.tertiary)
                Text(caption)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.2), value: caption)
            }
            .font(.system(size: 10))
        }
    }

    private func tile(_ mode: DisplayMode, index: Int) -> some View {
        let selected = mode.id == selectedID
        let isDefault = mode.id == display.defaultModeID
        let count = max(display.presets.count - 1, 1)
        let fontSize = 17 - 8 * CGFloat(index) / CGFloat(count)

        return Button {
            onSelect(mode)
        } label: {
            Text("Aa")
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.brand)
                            .matchedGeometryEffect(id: "selection", in: selection)
                            .shadow(color: Color.brand.opacity(0.35), radius: 4, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(hovered == mode.id ? 0.11 : 0.06))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isDefault {
                        Circle()
                            .fill(selected ? Color.white : Color.brand)
                            .frame(width: 4, height: 4)
                            .padding(5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                if inside { hovered = mode.id } else if hovered == mode.id { hovered = nil }
            }
        }
        .help(isDefault ? "\(mode.label) (Default)" : mode.label)
    }
}

// MARK: - Controls

/// Capsule slider with an animated fill, an inline symbol and a percentage readout.
struct PillSlider: View {
    @Binding var value: Double
    let symbol: String
    var tint: Color = .brand

    @State private var dragging = false
    @State private var hovering = false
    private let height: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(hovering || dragging ? 0.1 : 0.07))

                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.8), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, width * value))
                    .animation(dragging ? .interactiveSpring(response: 0.12) : .smooth(duration: 0.25), value: value)

                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 14)
                    Spacer()
                    Text("\(Int((value * 100).rounded()))%")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(value > 0.88 ? Color.white : Color.secondary)
                        .contentTransition(.numericText(value: value))
                        .animation(.smooth(duration: 0.2), value: value)
                }
                .padding(.horizontal, 6)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        value = min(max(gesture.location.x / width, 0), 1)
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: height)
        .scaleEffect(dragging ? 1.015 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct CapsuleButton: View {
    let title: String
    var prominent = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(prominent ? Color.brand.opacity(hovering ? 0.85 : 1) : Color.primary.opacity(hovering ? 0.14 : 0.08))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let symbol: String
    var active = false
    var help = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.primary.opacity(0.75))
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(active ? Color.brand : Color.primary.opacity(hovering ? 0.12 : 0.0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
        .help(help)
    }
}

/// The app's mark: a sunrise gradient squircle with a sun.
struct AppBadge: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.2), Color(red: 0.93, green: 0.27, blue: 0.45), Color(red: 0.42, green: 0.27, blue: 0.85)],
                                     startPoint: .top, endPoint: .bottom))
            Image(systemName: "sun.max.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
