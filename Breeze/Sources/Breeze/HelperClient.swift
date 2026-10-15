import FanCore
import Foundation

/// Talks to the privileged helper over XPC, and installs/uninstalls it.
@MainActor
final class HelperClient {
    static let shared = HelperClient()

    private var connection: NSXPCConnection?

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: HelperConstants.plistPath)
            && FileManager.default.fileExists(atPath: HelperConstants.installedPath)
    }

    private func makeConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: HelperConstants.label, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        let reset: () -> Void = { Task { @MainActor in HelperClient.shared.connection = nil } }
        connection.invalidationHandler = reset
        connection.interruptionHandler = reset
        connection.resume()
        self.connection = connection
        return connection
    }

    /// Calls the helper; exactly one of the reply or the error path runs.
    private func call<T: Sendable>(fallback: T, _ body: @escaping (FanHelperProtocol, @escaping (T) -> Void) -> Void) async -> T {
        let connection = makeConnection()
        return await withCheckedContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: fallback)
            }
            guard let helper = proxy as? FanHelperProtocol else {
                continuation.resume(returning: fallback)
                return
            }
            body(helper) { continuation.resume(returning: $0) }
        }
    }

    func version() async -> String? {
        await call(fallback: nil as String?) { helper, done in helper.version { done($0) } }
    }

    func setFan(_ index: Int, rpm: Double) async -> Bool {
        await call(fallback: false) { helper, done in helper.setFan(index, rpm: rpm) { done($0) } }
    }

    func setAutomatic() async -> Bool {
        await call(fallback: false) { helper, done in helper.setAutomatic { done($0) } }
    }

    /// Blocking variant for app termination (reply arrives on an XPC queue, not the main thread).
    func setAutomaticBlocking(timeout: TimeInterval = 1.5) {
        guard isInstalled else { return }
        let semaphore = DispatchSemaphore(value: 0)
        let proxy = makeConnection().remoteObjectProxyWithErrorHandler { _ in semaphore.signal() }
        guard let helper = proxy as? FanHelperProtocol else { return }
        helper.setAutomatic { _ in semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + timeout)
    }

    // MARK: Install

    /// Copies the helper into /Library and registers it with launchd (asks for an administrator password).
    func install() -> String? {
        guard let helper = Bundle.main.url(forAuxiliaryExecutable: "BreezeHelper") else {
            return "The helper is missing from the app bundle."
        }
        let plist: [String: Any] = [
            "Label": HelperConstants.label,
            "ProgramArguments": [HelperConstants.installedPath],
            "MachServices": [HelperConstants.label: true],
            "RunAtLoad": true,
        ]
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(HelperConstants.label).plist")
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: temp)
        } catch {
            return error.localizedDescription
        }
        defer { try? FileManager.default.removeItem(at: temp) }

        let label = HelperConstants.label
        let target = q(HelperConstants.installedPath)
        let plistPath = q(HelperConstants.plistPath)
        let script = [
            "/bin/launchctl bootout system/\(label) 2>/dev/null; true",
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/bin/cp \(q(helper.path)) \(target)",
            "/usr/sbin/chown root:wheel \(target)",
            "/bin/chmod 755 \(target)",
            "/bin/cp \(q(temp.path)) \(plistPath)",
            "/usr/sbin/chown root:wheel \(plistPath)",
            "/bin/chmod 644 \(plistPath)",
            "/bin/launchctl bootstrap system \(plistPath)",
        ].joined(separator: " && ")
        connection?.invalidate()
        connection = nil
        return runAsAdmin(script)
    }

    func uninstall() -> String? {
        connection?.invalidate()
        connection = nil
        let script = "/bin/launchctl bootout system/\(HelperConstants.label) 2>/dev/null; /bin/rm -f \(q(HelperConstants.plistPath)) \(q(HelperConstants.installedPath))"
        return runAsAdmin(script)
    }

    private func q(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runAsAdmin(_ command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        if let error {
            return error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        }
        return nil
    }
}
