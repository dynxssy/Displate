import FanCore
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: FanModel

    var body: some View {
        VStack(spacing: 8) {
            header

            if model.showWelcome {
                WelcomeCard(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            StatusCard(model: model)

            if model.hasFans {
                ModeCard(model: model)
                if model.mode != .auto && model.helperState != .ready {
                    HelperCard(model: model)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            } else if model.hasReading {
                Label(SMC.shared.isAvailable ? "This Mac has no fans — showing temperatures only."
                                             : "Can't read this Mac's sensors (no SMC access, e.g. in a virtual machine).",
                      systemImage: SMC.shared.isAvailable ? "wind" : "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
        }
        .padding(10)
        .frame(width: 340)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: model.mode)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: model.helperState)
    }

    private var header: some View {
        HStack(spacing: 8) {
            AppBadge(size: 22)
            Text("Breeze")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            IconButton(symbol: "gearshape.fill", help: "Settings") {
                SettingsWindowController.shared.show()
            }
            IconButton(symbol: "power", help: "Quit Breeze (fans return to automatic)") {
                NSApp.terminate(nil)
            }
        }
        .padding(.leading, 4)
        .padding(.bottom, 2)
    }
}

// MARK: - Welcome

private struct WelcomeCard: View {
    @ObservedObject var model: FanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.wave.fill").foregroundStyle(.yellow)
                Text("Breeze lives in your menu bar")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            Text("Watch temperatures, set a fixed fan speed, or let a curve follow the temperature. Fans always return to automatic when Breeze quits.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                CapsuleButton(title: "Got it") { model.dismissWelcome() }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color.cyan.opacity(0.16), Color.indigo.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

// MARK: - Status

private struct StatusCard: View {
    @ObservedObject var model: FanModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                SpinningFan(speed: model.hasFans ? model.averageFanFraction : 0, active: model.hasFans && model.fans.contains { $0.actual > 0 })
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        TemperatureLabel(title: "CPU", value: model.temperatures.cpu ?? model.temperatures.hottest, model: model, large: true)
                        TemperatureLabel(title: "GPU", value: model.temperatures.gpu, model: model, large: false)
                    }
                    TemperatureSparkline(values: model.history)
                        .frame(height: 22)
                }
            }

            ForEach(model.fans) { fan in
                FanRow(fan: fan, showName: model.fans.count > 1)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

private struct TemperatureLabel: View {
    let title: String
    let value: Double?
    @ObservedObject var model: FanModel
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(model.format(value))
                .font(.system(size: large ? 26 : 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value == nil ? Color.secondary : temperatureColor(value))
                .contentTransition(.numericText(value: value ?? 0))
        }
    }
}

/// A fan glyph that spins proportionally to the real fan speed.
private struct SpinningFan: View {
    let speed: Double
    let active: Bool

    /// Accumulated angle; a class so updating it while drawing doesn't invalidate the view.
    private final class Phase {
        var angle = 0.0
        var last: Date?
    }

    @State private var phase = Phase()

    var body: some View {
        TimelineView(.animation(paused: !active)) { context in
            Image(systemName: "fan.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                .rotationEffect(.degrees(rotation(at: context.date)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Circle().fill(Color.blue.opacity(0.1)))
        }
    }

    private func rotation(at date: Date) -> Double {
        let rate = active ? 120 + 900 * speed : 0 // degrees per second
        let elapsed = phase.last.map { min(date.timeIntervalSince($0), 0.1) } ?? 0
        phase.angle = (phase.angle + rate * elapsed).truncatingRemainder(dividingBy: 360)
        phase.last = date
        return phase.angle
    }
}

private struct TemperatureSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            if values.count > 1, let low = values.min(), let high = values.max() {
                let range = max(high - low, 8)
                let floor = low - (range - (high - low)) / 2
                let step = geometry.size.width / CGFloat(89)
                let offset = geometry.size.width - step * CGFloat(values.count - 1)
                let line = Path { builder in
                    for (index, value) in values.enumerated() {
                        let point = CGPoint(x: offset + CGFloat(index) * step,
                                            y: geometry.size.height * (1 - (value - floor) / range))
                        if index == 0 { builder.move(to: point) } else { builder.addLine(to: point) }
                    }
                }
                line.stroke(LinearGradient(colors: [.green, .yellow, .orange], startPoint: .bottom, endPoint: .top),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct FanRow: View {
    let fan: FanInfo
    let showName: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(showName ? fan.name : "Fan")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if fan.isManual {
                    Text("MANUAL")
                        .font(.system(size: 8, weight: .heavy))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.blue.opacity(0.18)))
                        .foregroundStyle(.blue)
                }
                Spacer()
                Text(fan.actual.rpmString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: fan.actual))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(5, geometry.size.width * fan.fraction))
                }
            }
            .frame(height: 5)
            HStack {
                Text(fan.minimum.rpmString)
                Spacer()
                Text(fan.maximum.rpmString)
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }
}

// MARK: - Modes

private struct ModeCard: View {
    @ObservedObject var model: FanModel
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 2) {
                ForEach(FanMode.allCases) { mode in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { model.mode = mode }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 12, weight: model.mode == mode ? .semibold : .medium))
                            .foregroundStyle(model.mode == mode ? Color.white : Color.primary.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background {
                                if model.mode == mode {
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .matchedGeometryEffect(id: "mode", in: selection)
                                        .shadow(color: Color.accentColor.opacity(0.3), radius: 4, y: 2)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.primary.opacity(0.07)))

            switch model.mode {
            case .auto:
                Label("macOS manages fan speed automatically.", systemImage: "sparkles")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            case .fixed:
                FixedControl(model: model)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            case .curve:
                CurveControl(model: model)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

private struct FixedControl: View {
    @ObservedObject var model: FanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PillSlider(value: $model.fixedSpeed, symbol: "fan.fill")
            if let fan = model.fans.first {
                Text("Target \(fan.rpm(forFraction: model.fixedSpeed).rpmString)\(model.fans.count > 1 ? " (each fan scaled to its range)" : "")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct CurveControl: View {
    @ObservedObject var model: FanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CurveEditor(curve: $model.curve, currentTemperature: model.controlTemperature, appliedSpeed: model.appliedSpeed,
                        fahrenheit: model.useFahrenheit)
                .frame(height: 150)

            HStack(spacing: 6) {
                ForEach([("Quiet", FanCurve.quiet), ("Balanced", FanCurve.balanced), ("Performance", FanCurve.performance)], id: \.0) { name, preset in
                    let active = model.curve.points == preset.points
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            model.curve = FanCurve(points: preset.points, sensor: model.curve.sensor)
                        }
                    } label: {
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.8))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(active ? Color.accentColor : Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(PressableStyle())
                }
                Spacer()
                Menu {
                    Picker("Follow", selection: $model.curve.sensor) {
                        ForEach(SensorKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium")
                        Text(model.curve.sensor.title)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Temperature the curve follows")
            }

            Text("Drag the points to shape the curve.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Temperature → fan speed chart with draggable points and a live marker.
struct CurveEditor: View {
    @Binding var curve: FanCurve
    let currentTemperature: Double?
    let appliedSpeed: Double?
    let fahrenheit: Bool
    @State private var dragging: Int?

    private let range = FanCurve.temperatureRange
    private let inset = EdgeInsets(top: 8, leading: 30, bottom: 18, trailing: 8)

    var body: some View {
        GeometryReader { geometry in
            let plot = CGRect(x: inset.leading, y: inset.top,
                              width: geometry.size.width - inset.leading - inset.trailing,
                              height: geometry.size.height - inset.top - inset.bottom)
            let sorted = curve.points.sorted { $0.temperature < $1.temperature }

            ZStack(alignment: .topLeading) {
                // Grid and axis labels
                ForEach([40.0, 60.0, 80.0, 100.0], id: \.self) { temperature in
                    let x = xPosition(temperature, in: plot)
                    Path { $0.move(to: CGPoint(x: x, y: plot.minY)); $0.addLine(to: CGPoint(x: x, y: plot.maxY)) }
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    Text(formatTemperature(temperature, fahrenheit: fahrenheit))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .position(x: x, y: plot.maxY + 10)
                }
                ForEach([0.0, 0.5, 1.0], id: \.self) { speed in
                    let y = yPosition(speed, in: plot)
                    Path { $0.move(to: CGPoint(x: plot.minX, y: y)); $0.addLine(to: CGPoint(x: plot.maxX, y: y)) }
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    Text("\(Int(speed * 100))%")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .position(x: plot.minX - 15, y: y)
                }

                // Curve and fill
                let line = curvePath(sorted, in: plot)
                Path { path in
                    path.addPath(line)
                    path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                    path.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                line.stroke(LinearGradient(colors: [.cyan, .blue, .indigo], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Live marker
                if let temperature = currentTemperature {
                    let x = xPosition(temperature, in: plot)
                    let y = yPosition(appliedSpeed ?? curve.speed(at: temperature), in: plot)
                    Path { $0.move(to: CGPoint(x: x, y: plot.minY)); $0.addLine(to: CGPoint(x: x, y: plot.maxY)) }
                        .stroke(temperatureColor(temperature).opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Circle()
                        .fill(temperatureColor(temperature))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .shadow(color: temperatureColor(temperature).opacity(0.6), radius: 4)
                        .position(x: x, y: y)
                        .animation(.smooth(duration: 0.5), value: temperature)
                }

                // Draggable points
                ForEach(Array(sorted.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(Color.white)
                        .frame(width: dragging == index ? 16 : 12, height: dragging == index ? 16 : 12)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2.5))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .overlay(alignment: .top) {
                            if dragging == index {
                                Text("\(formatTemperature(point.temperature, fahrenheit: fahrenheit)) · \(Int((point.speed * 100).rounded()))%")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.regularMaterial))
                                    .fixedSize()
                                    .offset(y: -24)
                            }
                        }
                        .contentShape(Circle().inset(by: -8))
                        .position(x: xPosition(point.temperature, in: plot), y: yPosition(point.speed, in: plot))
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("curve"))
                                .onChanged { value in
                                    dragging = index
                                    move(index, to: value.location, in: plot, sorted: sorted)
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragging = nil }
                                }
                        )
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
                }
            }
            .coordinateSpace(name: "curve")
        }
    }

    private func xPosition(_ temperature: Double, in plot: CGRect) -> CGFloat {
        plot.minX + plot.width * (min(max(temperature, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func yPosition(_ speed: Double, in plot: CGRect) -> CGFloat {
        plot.maxY - plot.height * min(max(speed, 0), 1)
    }

    private func curvePath(_ points: [FanCurve.Point], in plot: CGRect) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: plot.minX, y: yPosition(first.speed, in: plot)))
            for point in points {
                path.addLine(to: CGPoint(x: xPosition(point.temperature, in: plot), y: yPosition(point.speed, in: plot)))
            }
            path.addLine(to: CGPoint(x: plot.maxX, y: yPosition(last.speed, in: plot)))
        }
    }

    /// Keeps points ordered (2° apart) and inside the chart.
    private func move(_ index: Int, to location: CGPoint, in plot: CGRect, sorted: [FanCurve.Point]) {
        var points = sorted
        let span = range.upperBound - range.lowerBound
        var temperature = range.lowerBound + Double((location.x - plot.minX) / plot.width) * span
        let lower = index > 0 ? points[index - 1].temperature + 2 : range.lowerBound
        let upper = index < points.count - 1 ? points[index + 1].temperature - 2 : range.upperBound
        temperature = min(max(temperature, lower), upper).rounded()
        let speed = min(max(Double((plot.maxY - location.y) / plot.height), 0), 1)
        points[index] = FanCurve.Point(temperature, (speed * 100).rounded() / 100)
        curve = FanCurve(points: points, sensor: curve.sensor)
    }
}

/// Capsule slider with an animated fill, an inline symbol and a percentage readout.
struct PillSlider: View {
    @Binding var value: Double
    let symbol: String
    var tint: Color = .accentColor

    @State private var dragging = false
    private let height: CGFloat = 26

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.8), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, width * value))
                    .animation(dragging ? .interactiveSpring(response: 0.12) : .smooth(duration: 0.25), value: value)
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 14)
                    Spacer()
                    Text("\(Int((value * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(value > 0.88 ? Color.white : Color.secondary)
                        .contentTransition(.numericText(value: value))
                }
                .padding(.horizontal, 7)
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
    }
}

// MARK: - Helper

private struct HelperCard: View {
    @ObservedObject var model: FanModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isError ? .orange : .blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            CapsuleButton(title: model.helperState == .notInstalled ? "Install" : "Reinstall") { model.installHelper() }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill((isError ? Color.orange : Color.blue).opacity(0.12)))
    }

    private var isError: Bool {
        if case .failed = model.helperState { return true }
        return false
    }

    private var icon: String { isError ? "exclamationmark.triangle.fill" : "lock.shield.fill" }

    private var title: String {
        switch model.helperState {
        case .notInstalled: return "One-time setup"
        case .outdated: return "Helper update needed"
        case .failed: return "Fan control unavailable"
        case .ready: return ""
        }
    }

    private var message: String {
        switch model.helperState {
        case .notInstalled: return "Changing fan speed needs a small helper. It asks for your password once."
        case .outdated: return "Breeze was updated; reinstall its helper."
        case .failed(let error): return error
        case .ready: return ""
        }
    }
}
