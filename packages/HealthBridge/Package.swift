// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HealthBridge",
    // iOS is the only platform HealthKit exists on. macOS is declared so the pure
    // mirror/zone/aggregation logic can be tested on the host without a simulator;
    // every HealthKit call sits behind `#if canImport(HealthKit)`.
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "HealthBridge", targets: ["HealthBridge"])],
    dependencies: [
        .package(path: "../AscensionCore")
    ],
    targets: [
        .target(
            name: "HealthBridge",
            dependencies: ["AscensionCore"]
        ),
        .testTarget(name: "HealthBridgeTests", dependencies: ["HealthBridge"])
    ]
)
