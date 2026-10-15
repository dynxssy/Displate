import Darwin
import FanCore
import Foundation

/// Root launch daemon that performs SMC writes for Breeze.
/// Safety: fans go back to automatic when Breeze disconnects, when no command arrives for
/// `HelperConstants.watchdogSeconds`, and when the daemon is stopped.

final class FanService: NSObject, FanHelperProtocol {
    private let queue = DispatchQueue(label: "BreezeHelper.smc")
    private var lastCommand = Date()
    private var manual = false

    func version(reply: @escaping (String) -> Void) {
        reply(HelperConstants.version)
    }

    func setFan(_ index: Int, rpm: Double, reply: @escaping (Bool) -> Void) {
        queue.async {
            self.lastCommand = Date()
            guard index >= 0, index < FanReader.count() else {
                reply(false)
                return
            }
            let ok = FanWriter.setManual(index) && FanWriter.setTarget(index, rpm: rpm)
            if ok { self.manual = true }
            reply(ok)
        }
    }

    func setAutomatic(reply: @escaping (Bool) -> Void) {
        queue.async {
            self.lastCommand = Date()
            self.manual = false
            reply(FanWriter.resetAll())
        }
    }

    func resetIfIdle() {
        queue.async {
            guard self.manual, Date().timeIntervalSince(self.lastCommand) > HelperConstants.watchdogSeconds else { return }
            self.manual = false
            FanWriter.resetAll()
        }
    }

    func resetNow() {
        queue.sync {
            self.manual = false
            FanWriter.resetAll()
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service = FanService()
    private var connections = 0
    private let lock = NSLock()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard Self.isTrustedClient(pid: connection.processIdentifier) else {
            NSLog("BreezeHelper: rejected connection from pid \(connection.processIdentifier)")
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = service
        lock.lock()
        connections += 1
        lock.unlock()
        let onEnd: () -> Void = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.connections -= 1
            let remaining = self.connections
            self.lock.unlock()
            if remaining <= 0 { self.service.resetNow() }
        }
        connection.invalidationHandler = onEnd
        connection.resume()
        return true
    }

    /// Only Breeze itself may control the fans.
    static func isTrustedClient(pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return String(cString: buffer).hasSuffix("/Breeze.app/Contents/MacOS/Breeze")
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.label)
listener.delegate = delegate
listener.resume()

// Return fans to automatic on SIGTERM (launchctl bootout, uninstall, shutdown).
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    delegate.service.resetNow()
    exit(0)
}
termination.resume()

let watchdog = DispatchSource.makeTimerSource(queue: .main)
watchdog.schedule(deadline: .now() + 5, repeating: 5)
watchdog.setEventHandler { delegate.service.resetIfIdle() }
watchdog.resume()

dispatchMain()
