// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FruitDock",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure domain. Deliberately depends on no UI framework so that every
        // decision the dock makes can be exercised without a display attached.
        .target(name: "FruitDockCore"),

        // AppKit shell. Owns windows and system APIs, holds no decisions. A
        // library rather than the executable itself so a test target can
        // depend on it — SwiftPM test targets cannot cleanly depend on an
        // executableTarget, and main.swift's top-level code is the obstacle.
        .target(
            name: "FruitDockUI",
            dependencies: ["FruitDockCore"]
        ),

        // Entry point only: constructs the composition root and hands off to
        // AppKit's run loop. Everything it touches lives in FruitDockUI, so
        // this stays the ~10 lines that made it untestable in the first place.
        .executableTarget(
            name: "FruitDockApp",
            dependencies: ["FruitDockUI"]
        ),

        .testTarget(
            name: "FruitDockCoreTests",
            dependencies: ["FruitDockCore"]
        ),

        .testTarget(
            name: "FruitDockUITests",
            dependencies: ["FruitDockUI", "FruitDockCore"]
        ),
    ]
)
