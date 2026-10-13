import Combine
import SwiftUI

struct MenuView: View {
    @ObservedObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 10) {
            header

            if state.displays.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No displays found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }

            ForEach(state.displays) { display in
                DisplayCard(display: display, state: state)
                    .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
            }

            footer
        }
        .padding(12)
        .frame(width: 360)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.displays.map(\.id))
        .onAppear { state.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            state.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppBadge(size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("Displate")
                    .font(.system(size: 14, weight: .semibold))
                Text(state.displays.count == 1 ? "1 display" : "\(state.displays.count) displays")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.displays.count > 1 {
                IconButton(symbol: "link", active: state.syncBrightness,
                           help: state.syncBrightness ? "Brightness is synced across displays" : "Sync brightness across displays") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { state.syncBrightness.toggle() }
                }
            }
            IconButton(symbol: "gearshape.fill", help: "Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack {
            if let up = state.shortcuts[.brightnessUp], let down = state.shortcuts[.brightnessDown] {
                Label("\(down.displayString) \(up.displayString)", systemImage: "keyboard")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
                    .help("Brightness shortcuts — they act on the display under the pointer")
            }
            Spacer()
            HoverTextButton(title: "Quit") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Display card

private struct DisplayCard: View {
    let display: DisplayInfo
    @ObservedObject var state: AppState
    @State private var expanded: Bool
    @Namespace private var selection

    init(display: DisplayInfo, state: AppState) {
        self.display = display
        self.state = state
        _expanded = State(initialValue: display.isMain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            PillSlider(
                value: Binding(get: { display.brightness }, set: { state.setBrightness($0, for: display.id) }),
                symbol: brightnessSymbol(display.brightness),
                tint: .accentColor
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

            if expanded {
                resolutionSection
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { expanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: display.isBuiltIn ? [.blue, .cyan] : [.purple, .pink],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(display.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if display.isMain && state.displays.count > 1 {
                            Text("MAIN")
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.primary.opacity(0.1)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(display.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Resolution")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if display.hasHiDPIModes {
                    HStack(spacing: 6) {
                        Text("HiDPI")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Toggle("HiDPI", isOn: Binding(
                            get: { display.currentMode?.isHiDPI ?? false },
                            set: { _ in state.toggleHiDPI(for: display.id) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(display.gridModes) { mode in
                    ResolutionChip(
                        mode: mode,
                        selected: isCurrent(mode),
                        namespace: selection
                    ) {
                        state.applyMode(mode.id, for: display.id)
                    }
                }
            }

            if display.refreshRates.count > 1 {
                HStack {
                    Text("Refresh rate")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Refresh rate", selection: Binding(
                        get: { display.currentMode?.refreshRate.rounded() ?? 0 },
                        set: { state.setRefreshRate($0, for: display.id) }
                    )) {
                        ForEach(display.refreshRates, id: \.self) { rate in
                            Text("\(Int(rate)) Hz").tag(rate)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(display.modes) { mode in
                        Button {
                            state.applyMode(mode.id, for: display.id)
                        } label: {
                            if mode.id == display.currentMode?.id {
                                Label(mode.label, systemImage: "checkmark")
                            } else {
                                Text(mode.label)
                            }
                        }
                    }
                } label: {
                    Text("All modes")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .fixedSize()

                Spacer()

                if !display.isBuiltIn {
                    if display.hasOverride {
                        HoverTextButton(title: "Remove HiDPI unlock") { state.removeHiDPIOverride(for: display.id) }
                    } else if !display.hasHiDPIModes {
                        HoverTextButton(title: "Unlock HiDPI modes…", prominent: true) { state.installHiDPIOverride(for: display.id) }
                    }
                }
            }
            .font(.system(size: 11))

            if display.hasDDC {
                HStack {
                    Text("Software dimming")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Software dimming", isOn: Binding(
                        get: { display.softwareDimmingForced },
                        set: { state.setSoftwareDimming($0, for: display.id) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .help("Dim with the graphics card instead of DDC (for monitors that ignore DDC brightness)")
            }
        }
        .padding(.top, 2)
    }

    private func isCurrent(_ mode: DisplayMode) -> Bool {
        guard let current = display.currentMode else { return false }
        return mode.width == current.width && mode.height == current.height
    }

    private func brightnessSymbol(_ value: Double) -> String {
        value < 0.33 ? "sun.min.fill" : value < 0.66 ? "sun.max" : "sun.max.fill"
    }
}

// MARK: - Controls

/// Capsule slider with an animated fill, an inline symbol and a percentage readout.
struct PillSlider: View {
    @Binding var value: Double
    let symbol: String
    var tint: Color = .accentColor

    @State private var dragging = false
    @State private var hovering = false
    private let height: CGFloat = 26

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fillWidth = max(height, width * value)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(hovering || dragging ? 0.1 : 0.075))

                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillWidth)
                    .animation(dragging ? .interactiveSpring(response: 0.12) : .smooth(duration: 0.25), value: value)

                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 16)
                    Spacer()
                    Text("\(Int((value * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(value > 0.9 ? Color.white : Color.secondary)
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
        .scaleEffect(dragging ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct ResolutionChip: View {
    let mode: DisplayMode
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("\(mode.width) × \(mode.height)")
                .font(.system(size: 11, weight: selected ? .semibold : .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 4, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(hovering ? 0.1 : 0.05))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(mode.label)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.primary.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(active ? Color.accentColor : Color.primary.opacity(hovering ? 0.12 : 0.06))
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

struct HoverTextButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(prominent ? Color.accentColor : (hovering ? Color.primary : Color.secondary))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
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
                .shadow(color: .black.opacity(0.15), radius: size * 0.04, y: size * 0.02)
        }
        .frame(width: size, height: size)
    }
}
