import Foundation

public enum SensorKind: String, Codable, CaseIterable, Sendable {
    case cpu, gpu, other
}

public struct SensorReading: Identifiable, Hashable, Sendable {
    public let key: String
    public let kind: SensorKind
    public let value: Double
    public var id: String { key }

    public init(key: String, kind: SensorKind, value: Double) {
        self.key = key
        self.kind = kind
        self.value = value
    }
}

public struct Temperatures: Equatable, Sendable {
    public var cpu: Double?
    public var gpu: Double?
    public var hottest: Double?
    public var sensors: [SensorReading] = []

    public init(cpu: Double? = nil, gpu: Double? = nil, hottest: Double? = nil, sensors: [SensorReading] = []) {
        self.cpu = cpu
        self.gpu = gpu
        self.hottest = hottest
        self.sensors = sensors
    }
}

/// Finds the SMC's temperature keys once, then reads them on demand.
public final class TemperatureMonitor: @unchecked Sendable {
    public static let shared = TemperatureMonitor()

    private let smc = SMC.shared
    private var keys: [(key: String, kind: SensorKind)]?
    private let lock = NSLock()

    /// Classifies by key prefix: Intel (TC, TG), Apple silicon M1/M2/M4 (Tp, Te / Tg), M3 (Tf0/Tf4 / Tf1/Tf2).
    static func kind(of key: String) -> SensorKind {
        let prefix2 = String(key.prefix(2))
        let prefix3 = String(key.prefix(3))
        if ["Tp", "Te", "TC"].contains(prefix2) || ["Tf0", "Tf4"].contains(prefix3) { return .cpu }
        if ["Tg", "TG"].contains(prefix2) || ["Tf1", "Tf2"].contains(prefix3) { return .gpu }
        return .other
    }

    private func discover() -> [(key: String, kind: SensorKind)] {
        lock.lock()
        defer { lock.unlock() }
        if let keys { return keys }
        let found = smc.allKeys()
            .filter { $0.hasPrefix("T") && ["flt ", "sp78"].contains(smc.type(of: $0) ?? "") }
            .filter { key in
                // Keep keys that currently report a plausible temperature.
                guard let value = smc.read(key) else { return false }
                return value > 5 && value < 130
            }
            .map { ($0, Self.kind(of: $0)) }
        keys = found
        return found
    }

    public func read() -> Temperatures {
        guard smc.isAvailable else { return Temperatures() }
        var result = Temperatures()
        var cpu: [Double] = []
        var gpu: [Double] = []
        for (key, kind) in discover() {
            guard let value = smc.read(key), value > 5, value < 130 else { continue }
            result.sensors.append(SensorReading(key: key, kind: kind, value: value))
            switch kind {
            case .cpu: cpu.append(value)
            case .gpu: gpu.append(value)
            case .other: break
            }
        }
        result.cpu = cpu.max()
        result.gpu = gpu.max()
        result.hottest = (cpu + gpu).max() ?? result.sensors.map(\.value).max()
        return result
    }
}
