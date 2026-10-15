import AppKit
import ServiceManagement
import SwiftUI

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case percent, gigabytes, icon
    var id: String { rawValue }
    var title: String {
        switch self {
        case .percent: return "Percentage"
        case .gigabytes: return "Memory used"
        case .icon: return "Icon only"
        }
    }
}

/// Per-row quit progress.
enum QuitState: Equatable {
    case quitting
    case stubborn     // still running after a graceful quit → offer Force Quit
    case needsAdmin   // owned by another user → offer to kill as administrator
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    private enum Keys {
        static let menuBarStyle = "menuBarStyle"
        static let showHUD = "showHUD"
        static let includeSystem = "includeSystemProcesses"
        static let welcomeDismissed = "welcomeDismissed"
    }

    @Published private(set) var memory = MemorySnapshot()
    @Published private(set) var history: [Double] = []
    @Published private(set) var groups: [ProcessGroup] = []
    @Published private(set) var models: [LoadedModel] = []
    @Published private(set) var quitStates: [String: QuitState] = [:]
    @Published private(set) var unloading: Set<String> = []
    @Published private(set) var showWelcome = !UserDefaults.standard.bool(forKey: Keys.welcomeDismissed)
    @Published var showAll = false
    @Published var search = ""

    @Published var menuBarStyle = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: Keys.menuBarStyle) ?? "") ?? .percent {
        didSet {
            UserDefaults.standard.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle)
            StatusBarController.shared.updateTitle()
        }
    }

    @Published var showHUD = UserDefaults.standard.object(forKey: Keys.showHUD) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showHUD, forKey: Keys.showHUD) }
    }

    @Published var includeSystemProcesses = UserDefaults.standard.object(forKey: Keys.includeSystem) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(includeSystemProcesses, forKey: Keys.includeSystem)
            refreshProcesses()
        }
    }

    @Published var launchAtLogin = false {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Unload: launch at login failed: \(error)")
            }
        }
    }

    private var memoryTimer: Timer?
    private var processTimer: Timer?
    private var scanning = false
    private let scanQueue = DispatchQueue(label: "Unload.scan", qos: .userInitiated)
    private static let historyLength = 60

    // MARK: Derived

    var aiGroups: [ProcessGroup] { groups.filter { $0.isAI && !$0.isProtected } }

    var aiFootprint: UInt64 {
        aiGroups.reduce(0) { $0 + $1.footprint } + models.filter { model in
            // Ollama runners already show up as processes; only count models not covered by them.
            model.source == .lmStudio && model.size > 0
        }.reduce(0) { $0 + $1.size }
    }

    var visibleGroups: [ProcessGroup] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            return groups.filter { group in
                group.name.lowercased().contains(query) || group.processes.contains {
                    $0.name.lowercased().contains(query) || String($0.pid) == query
                }
            }
        }
        return showAll ? groups : Array(groups.prefix(5))
    }

    // MARK: Lifecycle

    func start() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshMemory()
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.refreshMemory() }
        }
    }

    /// Faster, process-level updates only while the panel is open.
    func panelDidOpen() {
        refreshMemory()
        refreshProcesses()
        refreshModels()
        processTimer?.invalidate()
        processTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                AppModel.shared.refreshProcesses()
                AppModel.shared.refreshModels()
            }
        }
    }

    func panelDidClose() {
        processTimer?.invalidate()
        processTimer = nil
        search = ""
    }

    func refreshMemory() {
        let snapshot = SystemMemory.snapshot()
        memory = snapshot
        history.append(snapshot.usedFraction)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
        StatusBarController.shared.updateTitle()
    }

    func refreshProcesses() {
        guard !scanning else { return }
        scanning = true
        let includeSystem = includeSystemProcesses
        scanQueue.async {
            let groups = ProcessScanner.shared.scan(includeOtherUsers: includeSystem)
            Task { @MainActor in
                let model = AppModel.shared
                model.scanning = false
                withAnimation(.smooth(duration: 0.3)) {
                    model.groups = groups
                    // Rows that disappeared no longer need a quit state.
                    let ids = Set(groups.map(\.id))
                    model.quitStates = model.quitStates.filter { ids.contains($0.key) }
                }
            }
        }
    }

    func refreshModels() {
        Task { @MainActor in
            let models = await LocalAI.loadedModels()
            if models != self.models {
                withAnimation(.smooth(duration: 0.3)) { self.models = models }
            }
        }
    }

    /// Used by `--render-preview`.
    func loadPreview(memory: MemorySnapshot, history: [Double], groups: [ProcessGroup], models: [LoadedModel]) {
        self.memory = memory
        self.history = history
        self.groups = groups
        self.models = models
    }

    func dismissWelcome() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showWelcome = false }
        UserDefaults.standard.set(true, forKey: Keys.welcomeDismissed)
    }

    // MARK: Quitting

    func quit(_ group: ProcessGroup, force: Bool = false) {
        guard !group.isProtected else { return }
        if quitStates[group.id] == .needsAdmin {
            killAsAdmin(group)
            return
        }
        let forcing = force || quitStates[group.id] == .stubborn
        let outcome = forcing ? ProcessKiller.forceKill(group.pids) : ProcessKiller.terminate(group)
        if outcome == .permissionDenied {
            withAnimation(.snappy) { quitStates[group.id] = .needsAdmin }
            return
        }
        withAnimation(.snappy) { quitStates[group.id] = .quitting }
        waitForExit(group, forced: forcing)
    }

    func quit(process: ProcessEntry, in group: ProcessGroup, force: Bool = false) {
        let single = ProcessGroup(id: "\(group.id)#\(process.pid)", name: process.name, bundlePath: nil, bundleID: nil,
                                  processes: [process], footprint: process.footprint, isAI: process.isAI,
                                  isProtected: group.isProtected, isOtherUser: process.isOtherUser)
        quit(single, force: force)
    }

    func quitState(for id: String) -> QuitState? { quitStates[id] }

    private func waitForExit(_ group: ProcessGroup, forced: Bool) {
        Task { @MainActor in
            for _ in 0..<(forced ? 8 : 14) {
                try? await Task.sleep(for: .milliseconds(250))
                if !group.pids.contains(where: ProcessKiller.isAlive) {
                    self.didFree(group)
                    return
                }
            }
            withAnimation(.snappy) { self.quitStates[group.id] = .stubborn }
        }
    }

    private func killAsAdmin(_ group: ProcessGroup) {
        if let error = ProcessKiller.killAsAdministrator(group.pids) {
            if !error.localizedCaseInsensitiveContains("cancel") {
                HUD.shared.show(symbol: "exclamationmark.triangle.fill", title: "Couldn't quit \(group.name)", subtitle: error)
            }
            return
        }
        withAnimation(.snappy) { quitStates[group.id] = .quitting }
        waitForExit(group, forced: true)
    }

    private func didFree(_ group: ProcessGroup) {
        withAnimation(.smooth(duration: 0.35)) {
            quitStates[group.id] = nil
            groups.removeAll { $0.id == group.id }
            for index in groups.indices {
                groups[index].processes.removeAll { group.pids.contains($0.pid) }
            }
            groups.removeAll { $0.processes.isEmpty }
        }
        HUD.shared.show(symbol: "checkmark.circle.fill", title: "Freed \(group.footprint.memoryString)", subtitle: group.name)
        refreshMemory()
        refreshProcesses()
    }

    // MARK: AI memory

    func unload(_ model: LoadedModel) {
        guard !unloading.contains(model.id) else { return }
        unloading.insert(model.id)
        let before = memory.used
        Task { @MainActor in
            let ok = await LocalAI.unload(model)
            self.unloading.remove(model.id)
            try? await Task.sleep(for: .milliseconds(600))
            self.refreshMemory()
            self.refreshModels()
            self.refreshProcesses()
            let freed = before > self.memory.used ? before - self.memory.used : model.size
            HUD.shared.show(symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            title: ok ? "Unloaded \(model.name)" : "Couldn't unload \(model.name)",
                            subtitle: ok && freed > 0 ? "Freed \(freed.memoryString)" : model.source.rawValue)
        }
    }

    /// Unloads every model and quits every AI process.
    func freeAllAIMemory() {
        let before = memory.used
        let targets = aiGroups
        let loaded = models
        Task { @MainActor in
            for model in loaded { _ = await LocalAI.unload(model) }
            for group in targets { _ = ProcessKiller.terminate(group) }
            try? await Task.sleep(for: .seconds(2))
            let survivors = targets.flatMap(\.pids).filter(ProcessKiller.isAlive)
            if !survivors.isEmpty { _ = ProcessKiller.forceKill(survivors) }
            try? await Task.sleep(for: .milliseconds(500))
            self.refreshMemory()
            self.refreshModels()
            self.refreshProcesses()
            let freed = before > self.memory.used ? before - self.memory.used : 0
            HUD.shared.show(symbol: "brain.head.profile", title: freed > 0 ? "Freed \(freed.memoryString)" : "AI memory cleared",
                            subtitle: "\(targets.count) processes, \(loaded.count) models")
        }
    }

    func purgeDiskCache() {
        let before = memory.cached
        if let error = ProcessKiller.purgeDiskCache() {
            if !error.localizedCaseInsensitiveContains("cancel") {
                HUD.shared.show(symbol: "exclamationmark.triangle.fill", title: "Purge failed", subtitle: error)
            }
            return
        }
        refreshMemory()
        let freed = before > memory.cached ? before - memory.cached : 0
        HUD.shared.show(symbol: "sparkles", title: "Disk cache purged", subtitle: freed > 0 ? "Released \(freed.memoryString)" : nil)
    }
}
