// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Unload",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Unload",
            path: "Sources/Unload",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
