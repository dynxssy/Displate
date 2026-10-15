import Foundation

/// Fan speed (0…1 between min and max RPM) as a function of temperature.
public struct FanCurve: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Hashable, Sendable {
        public var temperature: Double
        public var speed: Double

        public init(_ temperature: Double, _ speed: Double) {
            self.temperature = temperature
            self.speed = speed
        }
    }

    public var points: [Point]
    public var sensor: SensorKind

    public init(points: [Point], sensor: SensorKind = .cpu) {
        self.points = points.sorted { $0.temperature < $1.temperature }
        self.sensor = sensor
    }

    /// Linear interpolation between points; flat outside them.
    public func speed(at temperature: Double) -> Double {
        let sorted = points.sorted { $0.temperature < $1.temperature }
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        if temperature <= first.temperature { return first.speed }
        if temperature >= last.temperature { return last.speed }
        for (a, b) in zip(sorted, sorted.dropFirst()) where temperature <= b.temperature {
            let t = (temperature - a.temperature) / max(b.temperature - a.temperature, 0.001)
            return a.speed + (b.speed - a.speed) * t
        }
        return last.speed
    }

    public static let temperatureRange: ClosedRange<Double> = 30...100

    public static let quiet = FanCurve(points: [.init(40, 0), .init(65, 0.1), .init(80, 0.45), .init(95, 1)])
    public static let balanced = FanCurve(points: [.init(40, 0), .init(55, 0.15), .init(72, 0.5), .init(88, 1)])
    public static let performance = FanCurve(points: [.init(35, 0.2), .init(50, 0.4), .init(65, 0.75), .init(80, 1)])
}

/// The privileged helper's XPC interface.
@objc public protocol FanHelperProtocol {
    func version(reply: @escaping (String) -> Void)
    /// Puts the fan in manual mode if needed and sets its target speed. Also acts as a heartbeat.
    func setFan(_ index: Int, rpm: Double, reply: @escaping (Bool) -> Void)
    func setAutomatic(reply: @escaping (Bool) -> Void)
}

public enum HelperConstants {
    public static let label = "app.displate.Breeze.helper"
    public static let version = "1"
    public static let installedPath = "/Library/PrivilegedHelperTools/\(label)"
    public static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    /// Without a command for this long, the helper returns the fans to automatic.
    public static let watchdogSeconds: TimeInterval = 30
}
