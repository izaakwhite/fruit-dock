// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FruitDock",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure domain. Deliberately depends on no UI framework so that every
        // decision the dock makes can be exercised without a display attached.
        .target(name: "FruitDockCore"),

        // AppKit shell. Owns windows and system APIs, holds no decisions.
        .executableTarget(
            name: "FruitDockApp",
            dependencies: ["FruitDockCore"]
        ),

        .testTarget(
            name: "FruitDockCoreTests",
            dependencies: ["FruitDockCore"]
        ),
    ]
)
