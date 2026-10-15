import CSMC
import Foundation
import IOKit

/// AppleSMC access with value decoding. Reading works for any user; writing needs root.
public final class SMC: @unchecked Sendable {
    public static let shared = SMC()

    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private var infoCache: [UInt32: (size: UInt32, type: UInt32)] = [:]

    public let isAvailable: Bool

    private init() {
        var connection: io_connect_t = 0
        isAvailable = SMCOpen(&connection) == KERN_SUCCESS
        self.connection = connection
    }

    deinit {
        if isAvailable { SMCClose(connection) }
    }

    // MARK: Keys

    public static func fourCC(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) { result = result << 8 | UInt32(byte) }
        for _ in min(string.utf8.count, 4)..<4 { result = result << 8 | 0x20 }
        return result
    }

    public static func string(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func info(_ key: UInt32) -> (size: UInt32, type: UInt32)? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = infoCache[key] { return cached }
        var size: UInt32 = 0
        var type: UInt32 = 0
        guard isAvailable, SMCGetKeyInfo(connection, key, &size, &type) == KERN_SUCCESS, size > 0 else { return nil }
        infoCache[key] = (size, type)
        return (size, type)
    }

    public func hasKey(_ key: String) -> Bool { info(Self.fourCC(key)) != nil }

    public func type(of key: String) -> String? { info(Self.fourCC(key)).map { Self.string($0.type) } }

    /// Every key the SMC exposes (a few thousand on Apple silicon).
    public func allKeys() -> [String] {
        guard let count = read("#KEY").map({ Int($0) }), count > 0 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(count)
        lock.lock()
        defer { lock.unlock() }
        for index in 0..<UInt32(count) {
            var key: UInt32 = 0
            if SMCKeyAtIndex(connection, index, &key) == KERN_SUCCESS { keys.append(Self.string(key)) }
        }
        return keys
    }

    // MARK: Reading

    public func readBytes(_ key: String) -> (type: String, bytes: [UInt8])? {
        let code = Self.fourCC(key)
        guard let info = info(code) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        lock.lock()
        let result = SMCReadKey(connection, code, info.size, &bytes)
        lock.unlock()
        guard result == KERN_SUCCESS else { return nil }
        return (Self.string(info.type), Array(bytes.prefix(Int(info.size))))
    }

    /// Reads and decodes a numeric key.
    public func read(_ key: String) -> Double? {
        guard let (type, bytes) = readBytes(key) else { return nil }
        return Self.decode(type: type, bytes: bytes)
    }

    static func decode(type: String, bytes: [UInt8]) -> Double? {
        func be16() -> UInt16 { bytes.count >= 2 ? UInt16(bytes[0]) << 8 | UInt16(bytes[1]) : 0 }
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "sp78": return Double(Int16(bitPattern: be16())) / 256
        case "sp87": return Double(Int16(bitPattern: be16())) / 128
        case "sp96": return Double(Int16(bitPattern: be16())) / 64
        case "fpe2": return Double(be16()) / 4
        case "fp88": return Double(be16()) / 256
        case "ui8 ", "si8 ", "flag": return bytes.first.map { Double($0) }
        case "ui16": return Double(be16())
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default: return nil
        }
    }

    // MARK: Writing (root only)

    @discardableResult
    public func write(_ key: String, _ value: Double) -> Bool {
        let code = Self.fourCC(key)
        guard let info = info(code), let bytes = Self.encode(type: Self.string(info.type), value: value, size: Int(info.size)) else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        return SMCWriteKey(connection, code, info.size, bytes) == KERN_SUCCESS
    }

    static func encode(type: String, value: Double, size: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: size)
        func putBE16(_ raw: UInt16) {
            guard size >= 2 else { return }
            bytes[0] = UInt8(raw >> 8)
            bytes[1] = UInt8(raw & 0xFF)
        }
        switch type {
        case "flt ":
            guard size >= 4 else { return nil }
            let bits = Float(value).bitPattern
            for index in 0..<4 { bytes[index] = UInt8((bits >> UInt32(index * 8)) & 0xFF) }
        case "fpe2": putBE16(UInt16(clamping: Int((value * 4).rounded())))
        case "fp88": putBE16(UInt16(clamping: Int((value * 256).rounded())))
        case "ui8 ", "flag": bytes[0] = UInt8(clamping: Int(value.rounded()))
        case "ui16": putBE16(UInt16(clamping: Int(value.rounded())))
        default: return nil
        }
        return bytes
    }
}
