// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WattageBar",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "WattageBar", targets: ["WattageBar"]) 
    ],
    targets: [
        .executableTarget(
            name: "WattageBar",
            path: "Sources/WattageBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)

