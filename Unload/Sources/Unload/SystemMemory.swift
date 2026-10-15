import Darwin
import Foundation
import IOKit

struct MemorySnapshot: Equatable {
    enum Pressure: Int {
        case normal, warning, critical

        var label: String {
            switch self {
            case .normal: return "Normal"
            case .warning: return "Elevated"
            case .critical: return "Critical"
            }
        }
    }

    var total: UInt64 = 0
    /// Anonymous memory owned by apps (Activity Monitor's "App Memory").
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    /// File-backed and purgeable pages macOS can drop at any time.
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    /// Memory allocated by the GPU (unified memory on Apple silicon, VRAM elsewhere).
    var gpuInUse: UInt64?
    var pressure: Pressure = .normal

    /// Activity Monitor's "Memory Used".
    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used + cached ? total - used - cached : 0 }
    var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

enum SystemMemory {
    private static let host = mach_host_self()

    static func snapshot() -> MemorySnapshot {
        var snapshot = MemorySnapshot()
        snapshot.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(host, &pageSize)
            let page = UInt64(pageSize)
            let anonymous = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            snapshot.app = (anonymous > purgeable ? anonymous - purgeable : 0) * page
            snapshot.wired = UInt64(stats.wire_count) * page
            snapshot.compressed = UInt64(stats.compressor_page_count) * page
            snapshot.cached = (UInt64(stats.external_page_count) + purgeable) * page
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            snapshot.swapUsed = swap.xsu_used
            snapshot.swapTotal = swap.xsu_total
        }

        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 {
            snapshot.pressure = level >= 4 ? .critical : level >= 2 ? .warning : .normal
        }

        snapshot.gpuInUse = gpuMemoryInUse()
        return snapshot
    }

    /// Reads the GPU driver's performance statistics from the IORegistry.
    private static func gpuMemoryInUse() -> UInt64? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var total: UInt64 = 0
        var found = false
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            for key in ["In use system memory", "vramUsedBytes", "VRAM,usedBytes"] {
                if let value = stats[key] as? NSNumber {
                    total += value.uint64Value
                    found = true
                    break
                }
            }
        }
        return found ? total : nil
    }
}

extension UInt64 {
    /// "7.8 GB", "512 MB"
    var memoryString: String {
        let gb = Double(self) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0f GB", gb) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(self) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
