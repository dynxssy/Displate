// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Breeze",
    platforms: [.macOS(.v14)],
    targets: [
        // Raw AppleSMC user client access (struct layout must match the kernel's exactly, hence C).
        .target(name: "CSMC", path: "Sources/CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        // SMC decoding, sensors, fan reading/writing and the helper's XPC protocol — shared by app and helper.
        .target(name: "FanCore", dependencies: ["CSMC"], path: "Sources/FanCore"),
        .executableTarget(
            name: "Breeze",
            dependencies: ["FanCore"],
            path: "Sources/Breeze",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]
        ),
        // Privileged launch daemon that performs SMC writes (fan speed needs root).
        .executableTarget(name: "BreezeHelper", dependencies: ["FanCore"], path: "Sources/BreezeHelper"),
    ]
)
