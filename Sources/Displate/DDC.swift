import CoreGraphics
import Foundation
import IOKit

/// DDC/CI control of external monitors on Apple silicon via IOAVService.
/// Functions are resolved at runtime; on Macs without them DDC is simply unavailable.
enum DDC {
    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> OpaquePointer?
    private typealias I2CFn = @convention(c) (OpaquePointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    private static let createFn: CreateFn? = symbol("IOAVServiceCreateWithService")
    private static let writeFn: I2CFn? = symbol("IOAVServiceWriteI2C")
    private static let readFn: I2CFn? = symbol("IOAVServiceReadI2C")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51
    static let brightnessVCP: UInt8 = 0x10
    static let contrastVCP: UInt8 = 0x12

    // MARK: Discovery

    private struct Candidate {
        let attributes: [String: Any]
        let service: OpaquePointer
    }

    /// Finds an IOAVService for each of the given external displays.
    static func services(for displays: [CGDirectDisplayID], names: [CGDirectDisplayID: String]) -> [CGDirectDisplayID: OpaquePointer] {
        guard !displays.isEmpty, let createFn else { return [:] }

        var candidates: [Candidate] = []
        var iterator: io_iterator_t = 0
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        // The framebuffer entry (with the display's EDID attributes) precedes its DCPAVServiceProxy in the tree.
        var lastAttributes: [String: Any]?
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }

            let name = registryName(entry)
            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                let displayAttributes = property(entry, "DisplayAttributes") as? [String: Any]
                lastAttributes = (displayAttributes?["ProductAttributes"] as? [String: Any]) ?? [:]
            } else if name == "DCPAVServiceProxy", let attributes = lastAttributes {
                lastAttributes = nil
                guard (property(entry, "Location") as? String) == "External" else { continue }
                IOObjectRetain(entry) // keep the service alive for the IOAVService
                if let service = createFn(kCFAllocatorDefault, entry) {
                    candidates.append(Candidate(attributes: attributes, service: service))
                } else {
                    IOObjectRelease(entry)
                }
            }
        }

        var result: [CGDirectDisplayID: OpaquePointer] = [:]
        var remaining = candidates
        for display in displays where !remaining.isEmpty {
            let scores = remaining.map { score($0.attributes, display: display, name: names[display]) }
            guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }) else { break }
            result[display] = remaining[best].service
            remaining.remove(at: best)
        }
        return result
    }

    private static func score(_ attributes: [String: Any], display: CGDirectDisplayID, name: String?) -> Int {
        var score = 0
        if let vendor = attributes["LegacyManufacturerID"] as? Int, vendor == Int(CGDisplayVendorNumber(display)) { score += 1 }
        if let product = attributes["ProductID"] as? Int, product == Int(CGDisplayModelNumber(display)) { score += 1 }
        if let serial = attributes["SerialNumber"] as? Int, serial != 0, serial == Int(CGDisplaySerialNumber(display)) { score += 1 }
        if let productName = attributes["ProductName"] as? String, productName == name { score += 1 }
        return score
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return "" }
        return String(cString: buffer)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    // MARK: VCP access

    @discardableResult
    static func write(_ service: OpaquePointer, vcp: UInt8, value: UInt16) -> Bool {
        guard let writeFn else { return false }
        var packet: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = packet[0..<5].reduce(UInt8(0x6E ^ 0x51), ^)

        var success = false
        for _ in 0..<2 { // some monitors drop the first write
            usleep(10_000)
            let result = packet.withUnsafeMutableBytes {
                writeFn(service, chipAddress, dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            if result == 0 { success = true }
        }
        return success
    }

    static func read(_ service: OpaquePointer, vcp: UInt8) -> (current: UInt16, max: UInt16)? {
        guard let writeFn, let readFn else { return nil }
        var request: [UInt8] = [0x82, 0x01, vcp, 0]
        request[3] = request[0..<3].reduce(UInt8(0x6E ^ 0x51), ^)

        for _ in 0..<3 {
            usleep(10_000)
            let written = request.withUnsafeMutableBytes {
                writeFn(service, chipAddress, dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            guard written == 0 else { continue }
            usleep(50_000)

            var reply = [UInt8](repeating: 0, count: 11)
            let read = reply.withUnsafeMutableBytes {
                readFn(service, chipAddress, dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            guard read == 0, reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp else { continue }
            let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
            if maximum > 0 { return (current, maximum) }
        }
        return nil
    }
}

/// One external monitor's DDC channel. Writes are serialized and coalesced per VCP code,
/// so dragging a slider never queues up a backlog of slow I2C transactions.
final class DDCService: @unchecked Sendable {
    let service: OpaquePointer
    private let queue = DispatchQueue(label: "Displate.DDC", qos: .userInitiated)
    private let lock = NSLock()
    private var pending: [UInt8: UInt16] = [:]
    private var writing = false
    private var maxValues: [UInt8: UInt16] = [:]

    init(service: OpaquePointer) {
        self.service = service
    }

    func set(_ vcp: UInt8, fraction: Double) {
        lock.lock()
        let maximum = maxValues[vcp] ?? 100
        pending[vcp] = UInt16((min(max(fraction, 0), 1) * Double(maximum)).rounded())
        let shouldStart = !writing
        writing = true
        lock.unlock()
        if shouldStart {
            queue.async { self.drain() }
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let entry = pending.first else {
                writing = false
                lock.unlock()
                return
            }
            pending[entry.key] = nil
            lock.unlock()
            DDC.write(service, vcp: entry.key, value: entry.value)
        }
    }

    /// Reads a VCP value as a 0...1 fraction; the completion runs on the main queue.
    func read(_ vcp: UInt8, completion: @escaping (Double?) -> Void) {
        queue.async {
            let result = DDC.read(self.service, vcp: vcp)
            if let result {
                self.lock.lock()
                self.maxValues[vcp] = result.max
                self.lock.unlock()
            }
            let fraction: Double? = result.map { min(1, Double($0.current) / Double($0.max)) }
            DispatchQueue.main.async { completion(fraction) }
        }
    }
}
