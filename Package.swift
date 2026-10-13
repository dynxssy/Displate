// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Displate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Displate",
            path: "Sources/Displate",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
