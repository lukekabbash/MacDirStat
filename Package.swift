// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskVisualizerModules",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Treemap", targets: ["Treemap"]),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: []
        ),
        .target(
            name: "Treemap",
            dependencies: ["Core"]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"]
        ),
    ]
)
