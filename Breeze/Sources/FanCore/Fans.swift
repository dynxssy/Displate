import Foundation

public struct FanInfo: Identifiable, Hashable, Sendable {
    public let index: Int
    public var actual: Double
    public var minimum: Double
    public var maximum: Double
    public var target: Double
    public var isManual: Bool

    public var id: Int { index }

    /// Current speed as 0…1 between minimum and maximum.
    public var fraction: Double {
        maximum > minimum ? min(max((actual - minimum) / (maximum - minimum), 0), 1) : 0
    }

    public var name: String { "Fan \(index + 1)" }

    public init(index: Int, actual: Double, minimum: Double, maximum: Double, target: Double, isManual: Bool) {
        self.index = index
        self.actual = actual
        self.minimum = minimum
        self.maximum = maximum
        self.target = target
        self.isManual = isManual
    }

    public func rpm(forFraction fraction: Double) -> Double {
        minimum + (maximum - minimum) * min(max(fraction, 0), 1)
    }
}

public enum FanReader {
    public static func count(_ smc: SMC = .shared) -> Int {
        Int(smc.read("FNum") ?? 0)
    }

    public static func fans(_ smc: SMC = .shared) -> [FanInfo] {
        guard smc.isAvailable else { return [] }
        let forcedMask = Int(smc.read("FS! ") ?? 0)
        return (0..<count(smc)).compactMap { index in
            guard let actual = smc.read("F\(index)Ac") else { return nil }
            let minimum = smc.read("F\(index)Mn") ?? 0
            let maximum = smc.read("F\(index)Mx") ?? max(actual, 1)
            let target = smc.read("F\(index)Tg") ?? actual
            let mode = smc.read("F\(index)Md").map { Int($0) }
            let manual = mode.map { $0 == 1 } ?? (forcedMask & (1 << index) != 0)
            return FanInfo(index: index, actual: max(actual, 0), minimum: minimum, maximum: maximum,
                           target: target, isManual: manual)
        }
    }
}

/// SMC writes for fan control. Must run as root (the helper).
public enum FanWriter {
    /// Puts a fan in manual mode. Apple silicon needs the "Ftst" unlock first, and thermalmonitord
    /// may take a moment to let go, so the mode write is retried.
    public static func setManual(_ index: Int, smc: SMC = .shared) -> Bool {
        let modeKey = "F\(index)Md"
        if smc.hasKey(modeKey) {
            if Int(smc.read(modeKey) ?? 0) == 1 { return true }
            if smc.hasKey("Ftst") { smc.write("Ftst", 1) }
            for _ in 0..<24 {
                if smc.write(modeKey, 1), Int(smc.read(modeKey) ?? 0) == 1 { return true }
                usleep(250_000)
            }
            return false
        }
        if smc.hasKey("FS! ") {
            let mask = Int(smc.read("FS! ") ?? 0) | (1 << index)
            return smc.write("FS! ", Double(mask))
        }
        return false
    }

    public static func setTarget(_ index: Int, rpm: Double, smc: SMC = .shared) -> Bool {
        let minimum = smc.read("F\(index)Mn") ?? 0
        let maximum = smc.read("F\(index)Mx") ?? rpm
        let clamped = min(max(rpm, minimum), maximum)
        return smc.write("F\(index)Tg", clamped)
    }

    public static func setAutomatic(_ index: Int, smc: SMC = .shared) -> Bool {
        let modeKey = "F\(index)Md"
        if smc.hasKey(modeKey) { return smc.write(modeKey, 0) }
        if smc.hasKey("FS! ") {
            let mask = Int(smc.read("FS! ") ?? 0) & ~(1 << index)
            return smc.write("FS! ", Double(mask))
        }
        return false
    }

    /// Hands every fan back to macOS.
    @discardableResult
    public static func resetAll(smc: SMC = .shared) -> Bool {
        var ok = true
        for index in 0..<FanReader.count(smc) where !setAutomatic(index, smc: smc) {
            ok = false
        }
        if smc.hasKey("Ftst") { smc.write("Ftst", 0) }
        return ok
    }
}
