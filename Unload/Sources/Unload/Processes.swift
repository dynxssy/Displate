import AppKit
import Darwin

/// One running process.
struct ProcessEntry: Identifiable, Hashable {
    let pid: pid_t
    let name: String
    let path: String
    /// Physical footprint — the "Memory" column in Activity Monitor (RSS for processes we can't inspect).
    let footprint: UInt64
    let isOtherUser: Bool
    /// e.g. "mlx_lm.server" for an interpreter running a script
    let detail: String?
    let isAI: Bool

    var id: pid_t { pid }
}

/// An app (all processes inside one .app bundle) or a standalone process.
struct ProcessGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let bundlePath: String?
    let bundleID: String?
    var processes: [ProcessEntry]
    var footprint: UInt64
    var isAI: Bool
    var isProtected: Bool
    var isOtherUser: Bool

    var subtitle: String {
        if processes.count == 1, let detail = processes[0].detail { return detail }
        if processes.count > 1 { return "\(processes.count) processes" }
        return isOtherUser ? "System process" : "Process \(processes[0].pid)"
    }

    var pids: [pid_t] { processes.map(\.pid) }
}

/// Scans every process. Not tied to the main actor; call from a background queue.
final class ProcessScanner: @unchecked Sendable {
    static let shared = ProcessScanner()

    private let lock = NSLock()
    private var argumentCache: [pid_t: (path: String, detail: String?, aiArgs: Bool)] = [:]
    private var bundleCache: [String: (name: String, id: String?)] = [:]
    private let ownUID = getuid()
    private let ownPID = getpid()

    static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "SystemUIServer", "ControlCenter",
        "coreaudiod", "logd", "opendirectoryd", "notifyd", "configd", "mds", "mds_stores", "syslogd",
        "UserEventAgent", "distnoted", "cfprefsd", "securityd", "trustd", "powerd", "hidd", "watchdogd",
    ]

    private static let aiKeywords = [
        "ollama", "llama", "lm studio", "lmstudio", "lms", "mlx", "comfyui", "koboldcpp", "whisper",
        "stable-diffusion", "stable_diffusion", "diffusionbee", "draw things", "gpt4all", "localai", "vllm",
        "text-generation", "invokeai", "fooocus", "msty", "jan.app", "anythingllm",
    ]

    private static let aiArgumentKeywords = [
        "mlx", "torch", "transformers", "diffusers", "llama", "vllm", "comfy", "gradio", "whisper",
        "ollama", "huggingface", "stable", "sdxl", "flux", "kobold", "exllama", "accelerate",
    ]

    private static let interpreters = ["python", "node", "uv", "ruby", "java", "deno", "bun"]

    func scan(includeOtherUsers: Bool) -> [ProcessGroup] {
        let pids = allPIDs()
        var entries: [ProcessEntry] = []
        var unreadable: [pid_t: String] = [:]
        var alive = Set<pid_t>()

        for pid in pids where pid > 0 {
            alive.insert(pid)
            let path = Self.path(for: pid)
            let name = Self.name(for: pid, path: path)
            if let footprint = Self.footprint(for: pid) {
                entries.append(makeEntry(pid: pid, name: name, path: path, footprint: footprint, otherUser: Self.uid(for: pid) != ownUID))
            } else if includeOtherUsers {
                unreadable[pid] = path.isEmpty ? name : path
            }
        }

        // Root-owned processes can't be inspected without privileges; `ps` can still report their RSS.
        if !unreadable.isEmpty {
            for (pid, rss) in Self.residentSizes() {
                guard let path = unreadable[pid] else { continue }
                let name = Self.name(for: pid, path: path)
                entries.append(ProcessEntry(pid: pid, name: name, path: path, footprint: rss, isOtherUser: true,
                                            detail: nil, isAI: Self.matchesAI(name: name, path: path)))
            }
        }

        lock.lock()
        argumentCache = argumentCache.filter { alive.contains($0.key) }
        lock.unlock()

        return group(entries)
    }

    // MARK: Entries

    private func makeEntry(pid: pid_t, name: String, path: String, footprint: UInt64, otherUser: Bool) -> ProcessEntry {
        var detail: String?
        var aiArgs = false
        let lowerName = name.lowercased()
        if !otherUser && Self.interpreters.contains(where: { lowerName.hasPrefix($0) }) {
            lock.lock()
            let cached = argumentCache[pid]
            lock.unlock()
            if let cached, cached.path == path {
                detail = cached.detail
                aiArgs = cached.aiArgs
            } else {
                let arguments = Self.arguments(for: pid)
                detail = Self.scriptDescription(arguments)
                let joined = arguments.joined(separator: " ").lowercased()
                aiArgs = Self.aiArgumentKeywords.contains { joined.contains($0) }
                lock.lock()
                argumentCache[pid] = (path, detail, aiArgs)
                lock.unlock()
            }
        }
        return ProcessEntry(pid: pid, name: name, path: path, footprint: footprint, isOtherUser: otherUser,
                            detail: detail, isAI: aiArgs || Self.matchesAI(name: name, path: path))
    }

    private static func matchesAI(name: String, path: String) -> Bool {
        let haystack = (name + " " + path).lowercased()
        return aiKeywords.contains { keyword in
            // short keywords must match a whole name, not a substring (e.g. "lms")
            keyword.count <= 3 ? name.lowercased() == keyword : haystack.contains(keyword)
        }
    }

    /// "python3 -m mlx_lm.server --model …" → "mlx_lm.server"; "node server.js" → "server.js"
    private static func scriptDescription(_ arguments: [String]) -> String? {
        guard arguments.count > 1 else { return nil }
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "-m", index + 1 < arguments.count { return arguments[index + 1] }
            if argument == "-c" { return "inline script" }
            if !argument.hasPrefix("-") { return (argument as NSString).lastPathComponent }
            index += 1
        }
        return nil
    }

    // MARK: Grouping

    private func group(_ entries: [ProcessEntry]) -> [ProcessGroup] {
        var groups: [String: ProcessGroup] = [:]
        for entry in entries {
            if let bundle = Self.outermostBundle(entry.path) {
                let info = bundleInfo(bundle)
                if var existing = groups[bundle] {
                    existing.processes.append(entry)
                    existing.footprint += entry.footprint
                    existing.isAI = existing.isAI || entry.isAI
                    existing.isOtherUser = existing.isOtherUser && entry.isOtherUser
                    existing.isProtected = existing.isProtected || isProtected(entry)
                    groups[bundle] = existing
                } else {
                    groups[bundle] = ProcessGroup(id: bundle, name: info.name, bundlePath: bundle, bundleID: info.id,
                                                  processes: [entry], footprint: entry.footprint, isAI: entry.isAI,
                                                  isProtected: isProtected(entry), isOtherUser: entry.isOtherUser)
                }
            } else {
                let key = "pid:\(entry.pid)"
                let name = entry.detail.map { "\(entry.name) · \($0)" } ?? entry.name
                groups[key] = ProcessGroup(id: key, name: entry.detail == nil ? entry.name : name, bundlePath: nil, bundleID: nil,
                                           processes: [entry], footprint: entry.footprint, isAI: entry.isAI,
                                           isProtected: isProtected(entry), isOtherUser: entry.isOtherUser)
            }
        }
        return groups.values
            .map { group in
                var group = group
                group.processes.sort { $0.footprint > $1.footprint }
                return group
            }
            .sorted { $0.footprint > $1.footprint }
    }

    private func isProtected(_ entry: ProcessEntry) -> Bool {
        entry.pid == ownPID || entry.pid == 1 || Self.protectedNames.contains(entry.name)
    }

    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/…" → "/Applications/Google Chrome.app"
    private static func outermostBundle(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private func bundleInfo(_ path: String) -> (name: String, id: String?) {
        lock.lock()
        if let cached = bundleCache[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let bundle = Bundle(path: path)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let info = (name, bundle?.bundleIdentifier)
        lock.lock()
        bundleCache[path] = info
        lock.unlock()
        return info
    }

    // MARK: libproc

    private func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    static func footprint(for pid: pid_t) -> UInt64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
    }

    private static func path(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : ""
    }

    private static func name(for pid: pid_t, path: String) -> String {
        if !path.isEmpty { return (path as NSString).lastPathComponent }
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : "pid \(pid)"
    }

    private static func uid(for pid: pid_t) -> uid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbsi_uid
    }

    private static func arguments(for pid: pid_t) -> [String] {
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        var argmaxMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argmaxMIB, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        var size = buffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 { index += 1 } // executable path
        while index < size && buffer[index] == 0 { index += 1 } // padding

        var arguments: [String] = []
        while arguments.count < Int(argc) && index < size {
            let start = index
            while index < size && buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    /// pid → resident size (bytes) for every process, via /bin/ps.
    private static func residentSizes() -> [pid_t: UInt64] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,rss="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return [:]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var result: [pid_t: UInt64] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = pid_t(parts[0]), let kb = UInt64(parts[1]) else { continue }
            result[pid] = kb * 1024
        }
        return result
    }
}

/// Quitting processes.
enum ProcessKiller {
    enum Outcome {
        case sent
        case permissionDenied
    }

    /// Graceful: asks apps to quit (so they can save) and sends SIGTERM to the rest.
    static func terminate(_ group: ProcessGroup) -> Outcome {
        if let bundleID = group.bundleID {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                app.terminate()
            }
        }
        return signal(group.pids, SIGTERM)
    }

    static func forceKill(_ pids: [pid_t]) -> Outcome {
        signal(pids, SIGKILL)
    }

    private static func signal(_ pids: [pid_t], _ signal: Int32) -> Outcome {
        var denied = false
        for pid in pids where kill(pid, signal) != 0 && errno == EPERM {
            denied = true
        }
        return denied ? .permissionDenied : .sent
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Kills root-owned processes after an administrator password prompt. Returns an error message on failure.
    static func killAsAdministrator(_ pids: [pid_t]) -> String? {
        let list = pids.map(String.init).joined(separator: " ")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"kill -9 \(list)\" with administrator privileges")?.executeAndReturnError(&error)
        if let error {
            return error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        }
        return nil
    }

    /// `purge`: drops the disk cache (needs an administrator password).
    static func purgeDiskCache() -> String? {
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"/usr/sbin/purge\" with administrator privileges")?.executeAndReturnError(&error)
        if let error {
            return error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        }
        return nil
    }
}
