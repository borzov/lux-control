// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LuxControl",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LuxControlCore", targets: ["LuxControlCore"]),
        .library(name: "LuxControlMac", targets: ["LuxControlMac"]),
        .executable(name: "LuxControlApp", targets: ["LuxControlApp"]),
    ],
    targets: [
        .target(name: "LuxControlCore"),
        .target(
            name: "LuxControlMac",
            dependencies: ["LuxControlCore"],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .executableTarget(
            name: "LuxControlApp",
            dependencies: ["LuxControlCore", "LuxControlMac"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "LuxControlCoreTests",
            dependencies: ["LuxControlCore"]
        ),
        .testTarget(
            name: "LuxControlMacTests",
            dependencies: ["LuxControlMac", "LuxControlCore"]
        ),
    ]
)
