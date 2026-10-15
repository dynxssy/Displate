import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            header

            if model.showWelcome {
                WelcomeCard(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            MemoryCard(model: model)

            if !model.models.isEmpty || !model.aiGroups.isEmpty {
                AICard(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            ProcessCard(model: model)
        }
        .padding(10)
        .frame(width: 340)
        .tint(.brand)
    }

    private var header: some View {
        HStack(spacing: 8) {
            AppBadge(size: 22)
            Text("Unload")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            IconButton(symbol: "sparkles", help: "Purge disk cache (asks for your password)") {
                model.purgeDiskCache()
            }
            IconButton(symbol: "gearshape.fill", help: "Settings") {
                SettingsWindowController.shared.show()
            }
            IconButton(symbol: "power", help: "Quit Unload") {
                NSApp.terminate(nil)
            }
        }
        .padding(.leading, 4)
        .padding(.bottom, 2)
    }
}

// MARK: - Welcome

private struct WelcomeCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.wave.fill").foregroundStyle(.yellow)
                Text("Unload lives in your menu bar")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            Text("See what's holding your memory and free it in one click. ⌥-click the ✕ to force quit right away.")
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
                .fill(LinearGradient(colors: [Color.teal.opacity(0.18), Color.blue.opacity(0.14)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

// MARK: - Memory overview

private struct MemoryCard: View {
    @ObservedObject var model: AppModel

    private var memory: MemorySnapshot { model.memory }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Gauge(fraction: memory.usedFraction, color: memory.pressure.color)
                    .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(memory.used.memoryString)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("of \(memory.total.memoryString)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(memory.pressure.color).frame(width: 7, height: 7)
                        Text("Pressure \(memory.pressure.label)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Sparkline(values: model.history, color: memory.pressure.color)
                        .frame(height: 20)
                        .padding(.top, 2)
                }
            }

            CompositionBar(memory: memory)

            HStack(spacing: 0) {
                Stat(color: .blue, title: "Apps", value: memory.app)
                Stat(color: .orange, title: "Wired", value: memory.wired)
                Stat(color: .purple, title: "Compressed", value: memory.compressed)
                Stat(color: .gray, title: "Cached", value: memory.cached)
            }

            if memory.swapUsed > 0 || memory.gpuInUse != nil {
                HStack(spacing: 12) {
                    if let gpu = memory.gpuInUse {
                        Label("GPU \(gpu.memoryString)", systemImage: "cpu")
                    }
                    if memory.swapUsed > 0 {
                        Label("Swap \(memory.swapUsed.memoryString)", systemImage: "arrow.left.arrow.right")
                    }
                    Spacer()
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

private struct Gauge: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 7)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: fraction)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: fraction))
                .animation(.smooth(duration: 0.3), value: fraction)
        }
    }
}

private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let points = values.suffix(60)
            if points.count > 1 {
                let step = geometry.size.width / CGFloat(59)
                let offset = geometry.size.width - step * CGFloat(points.count - 1)
                let line = Path { builder in
                    for (index, value) in points.enumerated() {
                        let point = CGPoint(x: offset + CGFloat(index) * step, y: geometry.size.height * (1 - value))
                        if index == 0 { builder.move(to: point) } else { builder.addLine(to: point) }
                    }
                }
                ZStack {
                    line
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    Path { fill in
                        fill.addPath(line)
                        fill.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        fill.addLine(to: CGPoint(x: offset, y: geometry.size.height))
                        fill.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
            }
        }
    }
}

private struct CompositionBar: View {
    let memory: MemorySnapshot

    var body: some View {
        GeometryReader { geometry in
            let total = max(Double(memory.total), 1)
            let parts: [(Color, UInt64)] = [(.blue, memory.app), (.orange, memory.wired), (.purple, memory.compressed), (.gray.opacity(0.6), memory.cached)]
            HStack(spacing: 1.5) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(part.0)
                        .frame(width: max(0, geometry.size.width * Double(part.1) / total - 1.5))
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
            .animation(.smooth(duration: 0.5), value: memory)
        }
        .frame(height: 8)
    }
}

private struct Stat: View {
    let color: Color
    let title: String
    let value: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value.memoryString)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - AI memory

private struct AICard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AI memory", systemImage: "brain.head.profile")
                    .font(.system(size: 12, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                Spacer()
                CapsuleButton(title: "Free all", symbol: "bolt.fill", tint: .pink) { model.freeAllAIMemory() }
                    .help("Unload every model and quit every AI process")
            }

            ForEach(model.models) { loaded in
                HStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.pink)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(loaded.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(loaded.size > 0 ? "\(loaded.source.rawValue) · \(loaded.size.memoryString)" : "\(loaded.source.rawValue) · loaded")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.unloading.contains(loaded.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        CapsuleButton(title: "Unload", tint: .pink, prominent: false) { model.unload(loaded) }
                    }
                }
            }

            if model.models.isEmpty {
                let total = model.aiGroups.reduce(0) { $0 + $1.footprint }
                Text("\(model.aiGroups.count) AI \(model.aiGroups.count == 1 ? "process" : "processes") using \(total.memoryString)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [Color.pink.opacity(0.12), Color.purple.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

// MARK: - Processes

private struct ProcessCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.showAll ? "All processes" : "Using the most memory")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if model.groups.count > 5 {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { model.showAll.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Text(model.showAll ? "Show less" : "Show all \(model.groups.count)")
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(model.showAll ? 180 : 0))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.brand)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)

            if model.showAll {
                SearchField(text: $model.search)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if model.groups.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 16)
            } else if model.showAll {
                ScrollView {
                    rows
                }
                .frame(height: min(CGFloat(max(model.visibleGroups.count, 1)) * 44 + 4, 360))
                .scrollIndicators(.automatic)
            } else {
                rows
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private var rows: some View {
        let groups = model.visibleGroups
        let largest = max(groups.first?.footprint ?? 1, 1)
        return LazyVStack(spacing: 2) {
            ForEach(groups) { group in
                ProcessRow(group: group, largest: largest, model: model)
            }
            if groups.isEmpty {
                Text("No matches")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search by name or PID", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

private struct ProcessRow: View {
    let group: ProcessGroup
    let largest: UInt64
    @ObservedObject var model: AppModel
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 9) {
                icon
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(group.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if group.isAI {
                            Text("AI")
                                .font(.system(size: 8.5, weight: .heavy))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.pink.opacity(0.2)))
                                .foregroundStyle(.pink)
                        }
                    }
                    Text(group.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text(group.footprint.memoryString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                QuitButton(id: group.id, isProtected: group.isProtected, model: model) { force in
                    model.quit(group, force: force)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 5)
            .padding(.bottom, 7)
            .overlay(alignment: .bottomLeading) {
                // Share of the largest entry, as a slim bar under the row.
                GeometryReader { geometry in
                    Capsule()
                        .fill(LinearGradient(colors: [barColor.opacity(0.9), barColor.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geometry.size.width * min(1, Double(group.footprint) / Double(largest))), height: 2.5)
                        .animation(.smooth(duration: 0.5), value: group.footprint)
                }
                .frame(height: 2.5)
                .padding(.leading, 39)
                .padding(.trailing, 6)
                .padding(.bottom, 2)
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
            .onTapGesture {
                guard group.processes.count > 1 else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { expanded.toggle() }
            }
            .onHover { hovering = $0 }
            .help(group.processes.count > 1 ? "Click to see its \(group.processes.count) processes" : group.processes[0].path)

            if expanded {
                VStack(spacing: 1) {
                    ForEach(group.processes) { process in
                        HStack(spacing: 8) {
                            Text(process.detail.map { "\(process.name) · \($0)" } ?? process.name)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(process.pid)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(process.footprint.memoryString)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            QuitButton(id: "\(group.id)#\(process.pid)", isProtected: group.isProtected, small: true, model: model) { force in
                                model.quit(process: process, in: group, force: force)
                            }
                        }
                        .padding(.leading, 39)
                        .padding(.trailing, 6)
                        .padding(.vertical, 2)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var barColor: Color {
        group.isAI ? .pink : group.footprint > 4 << 30 ? .orange : .blue
    }

    @ViewBuilder
    private var icon: some View {
        if let bundle = group.bundlePath {
            Image(nsImage: IconCache.icon(for: bundle))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: group.isAI ? "brain.head.profile" : group.isOtherUser ? "gearshape.2.fill" : "terminal.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(group.isAI ? Color.pink.gradient : group.isOtherUser ? Color.gray.gradient : Color.indigo.gradient)
                )
        }
    }
}

/// ✕ → spinner while quitting → "Force Quit" if it won't die → "Admin" for system processes.
private struct QuitButton: View {
    let id: String
    let isProtected: Bool
    var small = false
    @ObservedObject var model: AppModel
    let action: (_ force: Bool) -> Void
    @State private var hovering = false

    var body: some View {
        Group {
            switch model.quitState(for: id) {
            case .quitting:
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: small ? 18 : 22, height: small ? 18 : 22)
            case .stubborn:
                CapsuleButton(title: "Force Quit", tint: .red) { action(true) }
                    .transition(.scale.combined(with: .opacity))
            case .needsAdmin:
                CapsuleButton(title: "Admin…", symbol: "lock.fill", tint: .orange) { action(true) }
                    .help("This process belongs to the system. Quit it with your administrator password.")
                    .transition(.scale.combined(with: .opacity))
            case nil:
                Button {
                    action(NSEvent.modifierFlags.contains(.option))
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: small ? 8.5 : 9.5, weight: .bold))
                        .foregroundStyle(hovering ? Color.white : Color.secondary)
                        .frame(width: small ? 18 : 22, height: small ? 18 : 22)
                        .background(Circle().fill(hovering ? Color.red : Color.primary.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .disabled(isProtected)
                .opacity(isProtected ? 0.3 : 1)
                .help(isProtected ? "Protected system process" : "Quit (⌥-click to force quit)")
            }
        }
        .animation(.snappy, value: model.quitState(for: id))
    }
}
